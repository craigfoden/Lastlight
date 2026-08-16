extends SceneTree
## Composes every generated sprite into one upscaled contact sheet so the art
## can actually be looked at. A 32x48 PNG opened at native size tells you
## nothing; a sheet at 6x on a neutral checkerboard shows silhouette, palette
## drift and stray pixels at a glance, which is the review that matters.
##
##   godot --headless --path <project> --script res://tools/art/preview_art.gd \
##       -- --out=<absolute png path>
##
## The sheet is a throwaway — it is not committed and nothing loads it.

const ZOOM := 6
const PAD := 4
const COLUMNS := 8


func _initialize() -> void:
	var out := "user://art_sheet.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.get_slice("=", 1)

	var names: Array[String] = []
	for group: Dictionary in [ArtSprites.CHARACTERS, ArtSprites.SMALL, ArtSprites.TILES]:
		for sprite_name: String in group:
			names.append(sprite_name)

	# Every cell is sized for the tallest sprite so the sheet stays a grid and
	# the eye can compare heights down a column — which is exactly the thing
	# that goes wrong when a roster is drawn one sprite at a time.
	var cell := Vector2i(32 * ZOOM + PAD * 2, 48 * ZOOM + PAD * 2)
	var rows: int = ceili(float(names.size()) / COLUMNS)
	var sheet := Image.create_empty(cell.x * COLUMNS, cell.y * rows, false,
			Image.FORMAT_RGBA8)
	_fill_checker(sheet)

	for i in names.size():
		var origin := Vector2i((i % COLUMNS) * cell.x + PAD, (i / COLUMNS) * cell.y + PAD)
		var path := "%s/%s.png" % [ArtGenerator.OUTPUT_DIR, names[i]]
		# Read the PNG bytes rather than Image.load_from_file: the latter warns
		# that loading a res:// image at runtime will not survive an export,
		# which is true and irrelevant for a tool, but the project's rule is
		# zero warnings and a tool that cries wolf trains people to ignore it.
		var src := Image.new()
		if src.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
			push_error("[Art] Missing %s — run generate_art.gd first." % path)
			quit(1)
			return
		src.convert(Image.FORMAT_RGBA8)
		for y in src.get_height():
			for x in src.get_width():
				var c := src.get_pixel(x, y)
				if c.a <= 0.0:
					continue
				for zy in ZOOM:
					for zx in ZOOM:
						var p := origin + Vector2i(x * ZOOM + zx, y * ZOOM + zy)
						sheet.set_pixel(p.x, p.y, _over(c, sheet.get_pixel(p.x, p.y)))

	var err := sheet.save_png(out)
	if err != OK:
		push_error("[Art] Could not write %s (error %d)." % [out, err])
		quit(1)
		return
	print("[Art] Contact sheet: %s (%d sprites)" % [out, names.size()])
	quit(0)


# A checkerboard rather than a flat colour: semi-transparent pixels (the drop
# shadow is nothing but) are invisible against any single background.
func _fill_checker(image: Image) -> void:
	var light := Color(0.42, 0.42, 0.46)
	var dark := Color(0.32, 0.32, 0.36)
	for y in image.get_height():
		for x in image.get_width():
			image.set_pixel(x, y, light if ((x / 8 + y / 8) % 2 == 0) else dark)


func _over(top: Color, bottom: Color) -> Color:
	return bottom.lerp(Color(top.r, top.g, top.b), top.a)
