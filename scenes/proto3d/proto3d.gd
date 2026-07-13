extends Node3D
## Session 8 prototype (branch-only): the "3D world + 2D billboard sprites"
## hybrid, as a look-and-feel slice. One grid cell = 1 unit. Proves out: an
## orthographic camera at the familiar angle, a real day/night sun with cast
## shadows, the glow tower as an actual light source, billboarded 2D sprites
## living in the lit world, camera-relative movement, and mouse→cell picking
## with a placement ghost. NOT wired to multiplayer or the real game loop —
## this scene exists to decide whether Lastlight commits to the 3D port.

const RANGER_TEXTURE := preload("res://assets/sprites/placeholder/player_ranger.svg")
const SHAMBLER_TEXTURE := preload("res://assets/sprites/placeholder/shambler.svg")

## Sprite scale: slightly over 32 px per unit so characters hold their own
## against the meshed trees (2D art is 48 px tall on a 32 px cell).
@export var sprite_pixel_size := 0.036
@export var move_speed := 6.0
@export var day_length := 14.0
@export var night_length := 8.0
@export var world_seed := 20260713
@export var tree_count := 70
@export var rock_count := 40
@export var scatter_min_radius := 5.0
@export var scatter_max_radius := 34.0

var _time := 0.0
var _player: Node3D
var _shambler: Node3D
var _sun: DirectionalLight3D
var _tower_light: OmniLight3D
var _env: Environment
var _ghost: MeshInstance3D
var _wall_mesh: BoxMesh
var _shambler_target := Vector3.ZERO
var _occupied := {}  # Vector2i cell -> true (placed walls)
var _sprites: Array[Sprite3D] = []
var _announced_day := false


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_tower()
	_scatter_props()
	_build_wall_row()
	_player = _spawn_billboard(RANGER_TEXTURE, Vector3(3, 0, 3))
	_shambler = _spawn_billboard(SHAMBLER_TEXTURE, Vector3(-6, 0, -5))
	_build_camera()
	_build_ghost()
	_parse_dev_args()
	print("[Proto3D] Hybrid slice ready: 1 unit = 1 cell, sun + tower light live")


func _process(delta: float) -> void:
	_time = fmod(_time + delta, day_length + night_length)
	_drive_daylight()
	_wander_shambler(delta)
	_update_ghost()


func _physics_process(delta: float) -> void:
	# Camera-relative WASD: "up" is screen-up, rotated onto the ground plane.
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var yaw := Basis(Vector3.UP, deg_to_rad(45.0))
	var dir := yaw * Vector3(input.x, 0.0, input.y)
	_player.position += dir * move_speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _mouse_cell()
		if not _occupied.has(cell):
			_occupied[cell] = true
			_place_wall(cell)
			print("[Proto3D] Wall placed at %s" % cell)


# --- world construction ------------------------------------------------------

func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	add_child(_sun)


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 90)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("2c3625")
	mat.roughness = 1.0
	plane.material = mat
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	add_child(ground)


func _build_tower() -> void:
	var column := BoxMesh.new()
	column.size = Vector3(1.3, 3.2, 1.3)
	var col_mat := StandardMaterial3D.new()
	col_mat.albedo_color = Color("e9e4d8")
	column.material = col_mat
	var body := MeshInstance3D.new()
	body.mesh = column
	body.position = Vector3(0, 1.6, 0)
	add_child(body)

	var gem := SphereMesh.new()
	gem.radius = 0.35
	gem.height = 0.7
	var gem_mat := StandardMaterial3D.new()
	gem_mat.albedo_color = Color("f2d94e")
	gem_mat.emission_enabled = true
	gem_mat.emission = Color("f2d94e")
	gem_mat.emission_energy_multiplier = 2.5
	gem.material = gem_mat
	var gem_node := MeshInstance3D.new()
	gem_node.mesh = gem
	gem_node.position = Vector3(0, 3.6, 0)
	add_child(gem_node)

	_tower_light = OmniLight3D.new()
	_tower_light.light_color = Color("ffd98a")
	_tower_light.omni_range = 16.0
	_tower_light.omni_attenuation = 0.8
	# No omni shadows: the Compatibility renderer (and ANGLE fallbacks) renders
	# the lit region black with them on. Directional shadows carry the look.
	_tower_light.shadow_enabled = false
	_tower_light.position = Vector3(0, 3.6, 0)
	add_child(_tower_light)


func _scatter_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	for i in tree_count:
		var pos := _ring_point(rng)
		var tree := Node3D.new()
		tree.position = pos
		add_child(tree)
		var trunk := MeshInstance3D.new()
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.14
		trunk_mesh.bottom_radius = 0.2
		trunk_mesh.height = 1.1
		var trunk_mat := StandardMaterial3D.new()
		trunk_mat.albedo_color = Color("5a3d24")
		trunk_mesh.material = trunk_mat
		trunk.mesh = trunk_mesh
		trunk.position.y = 0.55
		tree.add_child(trunk)
		var canopy := MeshInstance3D.new()
		var canopy_mesh := SphereMesh.new()
		var canopy_scale := rng.randf_range(0.65, 0.95)
		canopy_mesh.radius = canopy_scale
		canopy_mesh.height = canopy_scale * 2.0
		var canopy_mat := StandardMaterial3D.new()
		canopy_mat.albedo_color = Color("2f6b2f")
		canopy_mat.roughness = 1.0
		canopy_mesh.material = canopy_mat
		canopy.mesh = canopy_mesh
		canopy.position.y = 1.5
		tree.add_child(canopy)
	for i in rock_count:
		var rock := MeshInstance3D.new()
		var rock_mesh := SphereMesh.new()
		rock_mesh.radius = 0.45
		rock_mesh.height = 0.55
		var rock_mat := StandardMaterial3D.new()
		rock_mat.albedo_color = Color("7a7d87")
		rock_mat.roughness = 1.0
		rock_mesh.material = rock_mat
		rock.mesh = rock_mesh
		rock.position = _ring_point(rng)
		rock.position.y = 0.1
		rock.scale = Vector3(1.0, 0.8, 0.8)
		add_child(rock)


func _ring_point(rng: RandomNumberGenerator) -> Vector3:
	var r_min := scatter_min_radius
	var r_max := scatter_max_radius
	var radius := sqrt(rng.randf() * (r_max * r_max - r_min * r_min) + r_min * r_min)
	var angle := rng.randf() * TAU
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


func _build_wall_row() -> void:
	_wall_mesh = BoxMesh.new()
	_wall_mesh.size = Vector3(1.0, 0.9, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("8d8d99")
	mat.roughness = 0.9
	_wall_mesh.material = mat
	for x in range(3, 8):
		var cell := Vector2i(x, 3)
		_occupied[cell] = true
		_place_wall(cell)


func _place_wall(cell: Vector2i) -> void:
	var wall := MeshInstance3D.new()
	wall.mesh = _wall_mesh
	wall.position = Vector3(cell.x + 0.5, 0.45, cell.y + 0.5)
	add_child(wall)


func _spawn_billboard(texture: Texture2D, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = at
	add_child(root)
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.pixel_size = sprite_pixel_size
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	# Unshaded on purpose: `shaded` billboards behave differently per driver
	# (full-bright on some, double-dimmed with our hand tint on others), so the
	# day/night tint in _drive_daylight is the ONLY thing lighting sprites.
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Feet on the ground: the sprite is centred, so lift by half its height.
	sprite.position.y = texture.get_height() * sprite_pixel_size / 2.0
	root.add_child(sprite)
	# `shaded` billboards fall back to unshaded on some Compatibility drivers
	# (full-bright ghosts at night), so day/night tint is applied by hand via
	# `modulate` in _drive_daylight — the 3D equivalent of CanvasModulate.
	_sprites.append(sprite)
	return root


func _build_camera() -> void:
	var pivot := Node3D.new()
	pivot.rotation_degrees = Vector3(-33.0, 45.0, 0.0)
	_player.add_child(pivot)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.0
	camera.position = Vector3(0, 0, 30)
	camera.far = 80.0
	pivot.add_child(camera)
	camera.current = true


func _build_ghost() -> void:
	_ghost = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 0.9, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 1.0, 0.55, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	_ghost.mesh = mesh
	add_child(_ghost)


# --- runtime behaviour -------------------------------------------------------

func _drive_daylight() -> void:
	var is_day := _time < day_length
	var sprite_tint: Color
	if is_day:
		# Sun arcs from low east to high noon to low west across the day.
		var t := _time / day_length
		var arc := sin(t * PI)
		var elevation := lerpf(18.0, 72.0, arc)
		_sun.rotation_degrees = Vector3(-elevation, -40.0 + t * 80.0, 0.0)
		_sun.light_energy = lerpf(0.35, 1.15, arc)
		_sun.light_color = Color(1.0, 0.93, 0.82).lerp(Color(1.0, 0.72, 0.5), 1.0 - arc)
		_env.background_color = Color("1c2418").lerp(Color("30402a"), arc)
		_env.ambient_light_color = Color("6b7a5e")
		_env.ambient_light_energy = lerpf(0.25, 0.6, arc)
		_tower_light.light_energy = 0.6
		sprite_tint = Color(1, 1, 1).lerp(Color(1.0, 0.82, 0.68), 1.0 - arc)
	else:
		var t := (_time - day_length) / night_length
		_sun.light_energy = 0.02
		_env.background_color = Color("0a0e12")
		_env.ambient_light_color = Color("2a3448")
		_env.ambient_light_energy = 0.2
		# The tower becomes the world's light: a slow, alive pulse.
		_tower_light.light_energy = 3.0 + sin(t * TAU * 3.0) * 0.25
		sprite_tint = Color(0.36, 0.4, 0.55)
	for sprite in _sprites:
		# Standing in the tower's pool warms you up — strongest at night.
		var glow_reach := clampf(1.0 - sprite.global_position.length() / _tower_light.omni_range, 0.0, 1.0)
		sprite.modulate = sprite_tint.lerp(Color(1.0, 0.9, 0.7), glow_reach * (0.35 if is_day else 0.85))
	if is_day != _announced_day:
		_announced_day = is_day
		print("[Proto3D] %s" % ("DAY begins" if is_day else "NIGHT begins — tower light takes over"))


func _wander_shambler(delta: float) -> void:
	if _shambler.position.distance_to(_shambler_target) < 0.4:
		var angle := randf() * TAU
		_shambler_target = Vector3(cos(angle), 0.0, sin(angle)) * randf_range(6.0, 12.0)
	var dir := (_shambler_target - _shambler.position).normalized()
	_shambler.position += dir * 1.6 * delta


func _mouse_cell() -> Vector2i:
	var camera := get_viewport().get_camera_3d()
	var mouse := get_viewport().get_mouse_position()
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(
			camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if hit == null:
		return Vector2i.ZERO
	return Vector2i(floori(hit.x), floori(hit.z))


func _update_ghost() -> void:
	var cell := _mouse_cell()
	_ghost.position = Vector3(cell.x + 0.5, 0.45, cell.y + 0.5)


# --- dev harness (mirrors game.gd's hooks) -----------------------------------

func _parse_dev_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot-at="):
			for stamp in arg.get_slice("=", 1).split(","):
				_save_screenshot_after(float(stamp))
		elif arg == "--omni-shadows":
			# Phase-1 renderer test: omni shadows are known-broken on some
			# Compatibility/ANGLE stacks (lit region renders black).
			_tower_light.shadow_enabled = true
			print("[Proto3D] Omni shadow test: tower light shadows ON")
		elif arg.begins_with("--quit-after-sec="):
			get_tree().create_timer(float(arg.get_slice("=", 1))).timeout.connect(
					func() -> void: get_tree().quit())


func _save_screenshot_after(delay_sec: float) -> void:
	await get_tree().create_timer(delay_sec).timeout
	var image := get_viewport().get_texture().get_image()
	var path := "user://proto_shot_%d.png" % int(delay_sec)
	image.save_png(path)
	print("[Proto3D] Screenshot saved to %s (%d fps)" % [
			ProjectSettings.globalize_path(path), Engine.get_frames_per_second()])
