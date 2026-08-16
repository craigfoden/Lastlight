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

## Frame animation (session 18). A sprite may be authored as several pixel maps
## instead of one, and they are written side by side into a single strip PNG —
## the frame is then a `Sprite3D.hframes`/`frame` pair, which costs nothing and
## needs no new asset type. SpriteAnimator reads the frame count back off the
## texture width, so nothing in a scene has to be told how many frames a
## character has.
##
## **Frame 0 is always the standing pose**, and every frame after it is a step
## of the walk cycle. That convention is what lets one animator drive every
## character without a per-sprite table.
##
## Almost none of the set is hand-drawn in frames yet, because drawing six
## characters' walk cycles is a real day of pixel work and it should be spent on
## the real art, not on the placeholders (the roadmap has said so since session
## 16). So a character with a single authored map gets a two-step walk DERIVED
## from it: each frame lifts one leg clear of the ground by a pixel. It is a
## stopgap and it looks like one up close — but at gameplay distance, on top of
## the walk bob, it is the difference between a figure walking and a figure
## sliding. The moment anyone authors real frames for a sprite, the derivation
## stops applying to it and nothing else changes.
##
## Rows below this one are "the legs" for the purpose of the derived walk. Set
## conservatively: every humanoid in the set splits into two legs by row 36, and
## lifting from above the split would tear the hips apart.
const WALK_LEG_TOP := 36


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
			{"size": CHARACTER_SIZE, "sprites": ArtSprites.CHARACTERS, "walks": true},
			{"size": SMALL_SIZE, "sprites": ArtSprites.SMALL, "walks": false},
			# Ground tiles are the same 32x32 and go through the same validator
			# and the same import settings; only how they are *used* differs
			# (a repeating shader sampler rather than a Sprite3D texture).
			{"size": SMALL_SIZE, "sprites": ArtSprites.TILES, "walks": false}]:
		var size: Vector2i = group["size"]
		for sprite_name: String in group["sprites"]:
			var frames := _frames_of(group["sprites"][sprite_name], group["walks"])
			if _write_sprite(sprite_name, frames, size):
				written += 1
			else:
				failed = true

	if failed:
		return -1
	print("[Art] Generated %d sprites into %s." % [written, OUTPUT_DIR])
	return written


# An entry in the art data is either one pixel map (an array of row strings) or
# several (an array of those). Both come back as a list of frames, so everything
# downstream has exactly one shape to handle.
static func _frames_of(entry: Array, derive_walk: bool) -> Array:
	if not entry.is_empty() and entry[0] is Array:
		return entry  # hand-authored frames; the derivation stays out of the way
	if not derive_walk:
		return [entry]
	return [entry, _lift_leg(entry, true), _lift_leg(entry, false)]


# One derived walk frame: the leg on the given side is raised a pixel clear of
# the ground, so the two derived frames alternate which foot is planted. Shifting
# the leg block UP (each row taking the row below it) rather than redrawing it
# keeps the outline with the leg — the bottom outline row simply moves up too.
static func _lift_leg(rows: Array, left: bool) -> Array:
	var lifted: Array = rows.duplicate()
	var span_start := 0 if left else CHARACTER_SIZE.x / 2
	var span_end := CHARACTER_SIZE.x / 2 if left else CHARACTER_SIZE.x
	for y in range(WALK_LEG_TOP, rows.size()):
		var row: String = String(rows[y])
		var below: String = String(rows[y + 1]) if y + 1 < rows.size() else ""
		var rebuilt := ""
		for x in row.length():
			if x < span_start or x >= span_end:
				rebuilt += row[x]
			elif x < below.length():
				rebuilt += below[x]
			else:
				# The last row of the lifted leg has nothing below it to take:
				# that is the foot leaving the ground.
				rebuilt += ArtPalette.TRANSPARENT
		lifted[y] = rebuilt
	return lifted


# Validates every pixel map against its declared size before drawing anything, so
# a row one character short is reported as "this sprite, this frame, this row"
# rather than showing up later as a column of transparent pixels nobody notices.
# Frames are written side by side into one strip (see the frame-animation note
# at the top of this file).
static func _write_sprite(sprite_name: String, frames: Array, size: Vector2i) -> bool:
	var image := Image.create_empty(size.x * frames.size(), size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for f in frames.size():
		var rows: Array = frames[f]
		if rows.size() != size.y:
			push_error("[Art] '%s' frame %d has %d rows, expected %d."
					% [sprite_name, f, rows.size(), size.y])
			return false
		for y in size.y:
			var row: String = rows[y]
			if row.length() != size.x:
				push_error("[Art] '%s' frame %d row %d is %d wide, expected %d."
						% [sprite_name, f, y, row.length(), size.x])
				return false
			for x in size.x:
				var key := row[x]
				if key == ArtPalette.TRANSPARENT:
					continue
				image.set_pixel(f * size.x + x, y, ArtPalette.color_of(key))

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
