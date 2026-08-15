class_name ArtGenerator
extends RefCounted
## Turns the hand-authored pixel maps in `art_sprites.gd` into PNGs on disk.
##
## The art is kept as text and compiled rather than stored as binary images for
## three reasons that all matter to a repo two people edit: a change to a sprite
## shows up in `git diff` as a picture of what changed, a palette-wide decision
## (every outline one step darker) is one edit rather than thirty repaints, and
## nobody needs an image editor installed to fix a stray pixel.
##
## Run it — the PNGs are committed, so this is only needed after editing the art:
##   godot --headless --path <project> --script res://tools/art/generate_art.gd
##
## The generated PNGs are the real assets. `assets/sprites/placeholder/` (SVG)
## is what they replaced and is kept only until every consumer has moved over.

const OUTPUT_DIR := "res://assets/sprites/pixel"

## Characters and enemies stand 32x48 with their feet on the bottom row; flat
## ground decals, world billboards and shot sprites are 32x32. Both numbers are
## the convention CLAUDE.md already documented for the placeholder art, so the
## Sprite3D anchors and `pixel_size` values in the scenes stay exactly as they
## are — this is a texture swap, not a rescale.
const CHARACTER_SIZE := Vector2i(32, 48)
const SMALL_SIZE := Vector2i(32, 32)


## Writes every sprite. Returns the number written, or -1 if any sprite was
## malformed — a partial art set is worse than an obvious failure, so a bad
## pixel map fails the whole run rather than shipping one broken texture.
static func generate_all() -> int:
	if not DirAccess.dir_exists_absolute(OUTPUT_DIR):
		var err := DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
		if err != OK:
			push_error("[Art] Could not create %s (error %d)." % [OUTPUT_DIR, err])
			return -1

	var written := 0
	var failed := false
	for group: Dictionary in [
			{"size": CHARACTER_SIZE, "sprites": ArtSprites.CHARACTERS},
			{"size": SMALL_SIZE, "sprites": ArtSprites.SMALL}]:
		var size: Vector2i = group["size"]
		for sprite_name: String in group["sprites"]:
			var rows: Array = group["sprites"][sprite_name]
			if _write_sprite(sprite_name, rows, size):
				written += 1
			else:
				failed = true

	if failed:
		return -1
	print("[Art] Generated %d sprites into %s." % [written, OUTPUT_DIR])
	return written


# Validates the pixel map against its declared size before drawing anything, so
# a row one character short is reported as "this sprite, this row" rather than
# showing up later as a column of transparent pixels nobody notices.
static func _write_sprite(sprite_name: String, rows: Array, size: Vector2i) -> bool:
	if rows.size() != size.y:
		push_error("[Art] '%s' has %d rows, expected %d."
				% [sprite_name, rows.size(), size.y])
		return false

	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in size.y:
		var row: String = rows[y]
		if row.length() != size.x:
			push_error("[Art] '%s' row %d is %d wide, expected %d."
					% [sprite_name, y, row.length(), size.x])
			return false
		for x in size.x:
			var key := row[x]
			if key == ArtPalette.TRANSPARENT:
				continue
			image.set_pixel(x, y, ArtPalette.color_of(key))

	var path := "%s/%s.png" % [OUTPUT_DIR, sprite_name]
	var err := image.save_png(path)
	if err != OK:
		push_error("[Art] Could not write %s (error %d)." % [path, err])
		return false
	_ensure_import_settings(path)
	return true


## Import settings pixel art cannot survive without, forced on every generated
## PNG so they cannot drift and a newly added sprite cannot quietly get them
## wrong. `detect_3d/compress_to` is the one that matters and the one nobody
## sets by hand: Godot watches for a texture being used in a 3D material and
## silently RE-IMPORTS it with VRAM compression, which is a lossy block codec.
## On photographic art you would never notice; on 32 px art it smears every
## hard edge and mottles the alpha, and because it happens on second run it
## looks like the art "broke by itself". Every sprite here is used in 3D, so
## the detection is guaranteed to fire and must be told to do nothing.
const IMPORT_PARAMS := {
	"detect_3d/compress_to": "0",
	"compress/mode": "0",  # lossless
	"mipmaps/generate": "false",  # a mipmap of pixel art is mush
	"process/fix_alpha_border": "false",  # nothing filters, so nothing to fix
}


static func _ensure_import_settings(png_path: String) -> void:
	var import_path := png_path + ".import"
	if not FileAccess.file_exists(import_path):
		_write_stub_import(import_path, png_path)
		return

	# Patch in place rather than rewriting: the file also carries the resource
	# UID and the imported-file paths, and clobbering the UID would break every
	# scene and resource that already points at this texture.
	var text := FileAccess.get_file_as_string(import_path)
	var lines := text.split("\n")
	var seen := {}
	for i in lines.size():
		var key := String(lines[i]).get_slice("=", 0)
		if IMPORT_PARAMS.has(key):
			lines[i] = "%s=%s" % [key, IMPORT_PARAMS[key]]
			seen[key] = true
	var out := "\n".join(lines)
	for key: String in IMPORT_PARAMS:
		if not seen.has(key):
			out += "%s=%s\n" % [key, IMPORT_PARAMS[key]]

	if out == text:
		return
	var file := FileAccess.open(import_path, FileAccess.WRITE)
	if file == null:
		push_warning("[Art] Could not update %s." % import_path)
		return
	file.store_string(out)


# A brand-new sprite has no .import until Godot next scans the project. Leave
# it a minimal one carrying our params; the importer fills in every default it
# does not find, and assigns the UID itself on that first import.
static func _write_stub_import(import_path: String, png_path: String) -> void:
	var body := "[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n"
	body += "[deps]\n\nsource_file=\"%s\"\n\n[params]\n\n" % png_path
	for key: String in IMPORT_PARAMS:
		body += "%s=%s\n" % [key, IMPORT_PARAMS[key]]
	var file := FileAccess.open(import_path, FileAccess.WRITE)
	if file == null:
		push_warning("[Art] Could not create %s." % import_path)
		return
	file.store_string(body)
