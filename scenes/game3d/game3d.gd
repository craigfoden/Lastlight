extends Node3D
## Phase-2 shell of the 3D game world (docs/PORT_PLAN.md): ground plane,
## environment, sun, the glow tower as a real light, and the deterministic
## WorldGen3D scatter. No players, building, or waves yet — later phases add
## them, and phase 7 drives the sun/environment from DayNightCycle. Launch it
## directly:
##   godot --rendering-method forward_plus --path . res://scenes/game3d/game3d.tscn
## Dev args (after --): --quit-after-sec=N, --screenshot-at=a,b (windowed).

## Debug fly-camera pan speed, world units per second (phase 3 replaces this
## rig with the player camera).
@export var pan_speed := 14.0

@onready var _camera_rig: Node3D = $CameraRig


func _ready() -> void:
	_parse_dev_args()
	print("[Game3D] World shell ready (%s / %s)" % [
			RenderingServer.get_current_rendering_method(),
			RenderingServer.get_current_rendering_driver_name()])


func _process(delta: float) -> void:
	# Camera-relative WASD pan, same yaw trick as the prototype: screen-up is
	# world 45 degrees on the ground plane.
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var yaw := Basis(Vector3.UP, deg_to_rad(45.0))
	_camera_rig.position += yaw * Vector3(input.x, 0.0, input.y) * pan_speed * delta


# --- dev harness (mirrors proto3d.gd until the real game args port over) -----

func _parse_dev_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot-at="):
			for stamp in arg.get_slice("=", 1).split(","):
				_save_screenshot_after(float(stamp))
		elif arg.begins_with("--quit-after-sec="):
			get_tree().create_timer(float(arg.get_slice("=", 1))).timeout.connect(
					func() -> void: get_tree().quit())


func _save_screenshot_after(delay_sec: float) -> void:
	await get_tree().create_timer(delay_sec).timeout
	var image := get_viewport().get_texture().get_image()
	var path := "user://game3d_shot_%d.png" % int(delay_sec)
	image.save_png(path)
	print("[Game3D] Screenshot saved to %s (%d fps)" % [
			ProjectSettings.globalize_path(path), Engine.get_frames_per_second()])
