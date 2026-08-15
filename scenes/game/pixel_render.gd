class_name PixelRender
extends Node
## Renders the 3D world at a low resolution and nearest-upscales it, so the
## mesh half of the game (towers, walls, trees, camp ruins) reads as pixel art
## alongside the billboard sprites instead of sitting behind them looking
## smooth. This is the whole visual identity in about thirty lines.
##
## It uses the root Viewport's own `scaling_3d_mode`, which is the reason this
## is a small change rather than a dangerous one. The obvious way to pixelate a
## 3D game is to reparent the world under a SubViewport — but every generated
## world node resolves its harvest RPCs BY NODE PATH (see GOTCHAS), the build
## system raycasts through camera/viewport coordinates, and moving the world
## would disturb both. `scaling_3d_mode` scales only the 3D buffer, in place:
## the scene tree, every node path, and mouse picking are all untouched, and
## the 2D HUD and minimap keep rendering at native resolution and stay sharp.
##
## Turn it off with `--no-pixel-render` to compare, or `pixel_render_enabled`
## on the Game node in the inspector.

## World units one texel of a character sprite covers — the `pixel_size` on the
## Sprite3D nodes, and the number the render resolution is derived from.
##
## The goal is that one texel of a sprite lands on exactly one rendered pixel,
## which is the difference between pixel art and a photograph of pixel art. Off
## 1:1, a 48 px sprite covers some fractional number of pixels and the renderer
## must choose which texels survive — so as a character walks, rows of them pop
## in and out ("pixel shimmer"). At 1:1 that cannot happen. Since the camera is
## orthogonal, its `size` is how many world units tall the view is, so the
## render height we want is simply `camera.size / texel_world_size`.
@export var texel_world_size := 0.036

## Used only until a camera is found. The Game scene starts on a wide fallback
## camera and swaps to the player's much tighter one when they spawn, so any
## value fixed at _ready would be measured against a camera about to be
## replaced — hence deriving it live rather than trusting a constant.
@export var fallback_render_height := 361

## Left true so a fresh clone looks like the game is meant to look. The look is
## strong and someone will want it off; that is what this and the dev arg are.
@export var enabled := true

var _previous_mode := Viewport.SCALING_3D_MODE_BILINEAR
var _previous_scale := 1.0
## Last camera size the scale was computed for, so the per-frame check is two
## float compares and only does real work when something actually changed.
var _last_camera_size := -1.0
var _last_window_height := -1


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--no-pixel-render":
			enabled = false

	# Headless renders no frames, so there is nothing to scale and no window to
	# measure — without this the smoke tests get two lines of nonsense
	# resolution in logs they assert against.
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return

	var viewport := get_viewport()
	_previous_mode = viewport.scaling_3d_mode
	_previous_scale = viewport.scaling_3d_scale
	if not enabled:
		print("[PixelRender] Disabled - 3D renders at native resolution.")
		set_process(false)
		return

	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_NEAREST
	_apply_scale()


# Watching rather than reacting to a signal, because the two things the scale
# depends on change in different ways: the window announces resizes, but the
# active camera is simply swapped out from under us when the local player
# spawns, and nothing emits anything when that happens.
func _process(_delta: float) -> void:
	if enabled:
		_apply_scale()


# The viewport is the root and outlives this scene, so a run that ends back at
# the menu must put it back rather than leave the whole app quietly scaled.
func _exit_tree() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	viewport.scaling_3d_mode = _previous_mode
	viewport.scaling_3d_scale = _previous_scale


func _apply_scale() -> void:
	var height := get_window().size.y
	if height <= 0 or texel_world_size <= 0.0:
		return

	# A perspective camera has no world-units-per-screen-height to derive from,
	# so it keeps the fallback rather than guessing.
	var camera_size := -1.0
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		camera_size = camera.size
	if is_equal_approx(camera_size, _last_camera_size) and height == _last_window_height:
		return
	_last_camera_size = camera_size
	_last_window_height = height

	var target := fallback_render_height
	if camera_size > 0.0:
		target = roundi(camera_size / texel_world_size)

	var viewport := get_viewport()
	# Clamped because the engine treats values above 1.0 as supersampling and
	# silently falls back to bilinear downsampling — a window shorter than the
	# target would otherwise turn the pixel look off without saying so.
	viewport.scaling_3d_scale = clampf(float(target) / float(height), 0.1, 1.0)
	print("[PixelRender] 3D at %d x %d (scale %.3f), 1:1 with %.3f world-unit texels." % [
			int(viewport.get_visible_rect().size.x * viewport.scaling_3d_scale),
			int(height * viewport.scaling_3d_scale),
			viewport.scaling_3d_scale,
			texel_world_size])
