class_name BuildController3D
extends Node3D
## Local-only build input for the 3D world: hotbar selection, the snapped
## ghost preview, and sending place/sell requests to the host. Never mutates
## game state itself — every action goes through BuildManager3D's
## host-validated RPCs. Cell picking is the prototype's ray-plane trick:
## project the mouse ray onto the ground plane and floor it.

signal selection_changed(type: BuildingType)

const GHOST_VALID := Color(0.55, 1.0, 0.55, 0.45)
const GHOST_INVALID := Color(1.0, 0.4, 0.4, 0.45)
## A cell far outside the grid region — "the mouse ray missed the ground";
## placement_error reports it as out of bounds.
const CELL_NOWHERE := Vector2i(1 << 20, 1 << 20)

var _build_manager: BuildManager3D
var _selected: BuildingType
var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D


func _ready() -> void:
	# Placeholder ghost: a translucent one-cell box (the real building's mesh
	# can replace it when the art pass lands).
	_ghost = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 0.9, 1.0)
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.albedo_color = GHOST_VALID
	mesh.material = _ghost_material
	_ghost.mesh = mesh
	_ghost.position = Vector3(0, 0.45, 0)
	_ghost.visible = false
	add_child(_ghost)


## Injected by the Game scene.
func setup(build_manager: BuildManager3D) -> void:
	_build_manager = build_manager


## Select if it isn't selected; put the hammer away if it is.
func toggle(type: BuildingType) -> void:
	select(null if type == _selected else type)


func select(type: BuildingType) -> void:
	_selected = type
	_ghost.visible = type != null
	selection_changed.emit(type)


func _unhandled_input(event: InputEvent) -> void:
	if _build_manager == null:
		return
	for i in mini(_build_manager.buildable_types.size(), 3):
		if event.is_action_pressed("build_select_%d" % (i + 1)):
			toggle(_build_manager.buildable_types[i])
			return
	if _selected != null:
		if event.is_action_pressed("build_cancel"):
			select(null)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("build_confirm"):
			_build_manager.request_place.rpc_id(1, _selected.id, _mouse_cell())
			# Consume the click so the player doesn't also fire their weapon.
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("sell"):
		if _build_manager.building_at(_mouse_cell()) != null:
			_build_manager.request_sell.rpc_id(1, _mouse_cell())


func _process(_delta: float) -> void:
	if _selected == null:
		return
	var cell := _mouse_cell()
	_ghost.position = _build_manager.cell_to_world(cell) + Vector3(0, 0.45, 0)
	var error := _build_manager.placement_error(
			_selected, cell, Network.local_player_class)
	_ghost_material.albedo_color = GHOST_VALID if error == "" else GHOST_INVALID


func _mouse_cell() -> Vector2i:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return CELL_NOWHERE
	var mouse := get_viewport().get_mouse_position()
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(
			camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if hit == null:
		return CELL_NOWHERE
	return _build_manager.world_to_cell(hit)
