class_name BuildController
extends Node3D
## Local-only build input for the 3D world: hotbar selection, sell mode, the
## snapped ghost preview, and sending place/sell requests to the host. Never
## mutates game state itself — every action goes through BuildManager's
## host-validated RPCs. Cell picking is the prototype's ray-plane trick:
## project the mouse ray onto the ground plane and floor it.

signal selection_changed(type: BuildingType)
## Sell mode toggled (X or the hotbar's Sell button). Mutually exclusive with
## a building selection — entering either leaves the other.
signal sell_mode_changed(active: bool)
## In sell mode, the building under the mouse changed (null = open ground).
signal sell_hover_changed(building: Building)

const GHOST_VALID := Color(0.55, 1.0, 0.55, 0.45)
const GHOST_INVALID := Color(1.0, 0.4, 0.4, 0.45)
## Sell mode's hover highlight: "this one comes down if you click".
const GHOST_SELL := Color(1.0, 0.55, 0.2, 0.5)
## A cell far outside the grid region — "the mouse ray missed the ground";
## placement_error reports it as out of bounds.
const CELL_NOWHERE := Vector2i(1 << 20, 1 << 20)

## How many number keys the input map defines (build_select_1..N). Every class
## currently lands on exactly 3 placeables — two shared plus one exclusive —
## which is a fact about today's data, not a rule. Give any class a fourth and
## it appears in the hotbar but stays click-only until a `build_select_4`
## action is added to project.godot (a merge-sensitive file: call it out).
const HOTBAR_KEYS := 3

var _build_manager: BuildManager
## This player's placeable list, in the same order the hotbar draws it, so
## key N and button N are always the same building.
var _my_types: Array[BuildingType] = []
var _selected: BuildingType
var _sell_mode := false
var _sell_hover: Building
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
func setup(build_manager: BuildManager) -> void:
	_build_manager = build_manager
	_my_types = build_manager.types_for_class(Network.local_player_class)


## Select if it isn't selected; put the hammer away if it is.
func toggle(type: BuildingType) -> void:
	select(null if type == _selected else type)


func select(type: BuildingType) -> void:
	if _sell_mode:
		_set_sell_mode(false)
	_selected = type
	_ghost.visible = type != null
	selection_changed.emit(type)


## X or the hotbar's Sell button. In sell mode the ghost rides the hovered
## building as a red "this comes down" highlight and LMB sells it.
func toggle_sell_mode() -> void:
	_set_sell_mode(not _sell_mode)


func _set_sell_mode(active: bool) -> void:
	if _sell_mode == active:
		return
	_sell_mode = active
	_ghost.visible = false
	_set_sell_hover(null)
	if active and _selected != null:
		# The hammer replaces the blueprint — drop the selection quietly
		# (calling select() here would immediately exit sell mode again).
		_selected = null
		selection_changed.emit(null)
	sell_mode_changed.emit(active)


func _set_sell_hover(building: Building) -> void:
	if building == _sell_hover:
		return
	_sell_hover = building
	sell_hover_changed.emit(building)


func _unhandled_input(event: InputEvent) -> void:
	if _build_manager == null:
		return
	for i in mini(_my_types.size(), HOTBAR_KEYS):
		if event.is_action_pressed("build_select_%d" % (i + 1)):
			toggle(_my_types[i])
			return
	if event.is_action_pressed("sell"):
		toggle_sell_mode()
		return
	if _selected != null:
		if event.is_action_pressed("build_cancel"):
			select(null)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("build_confirm"):
			_build_manager.request_place.rpc_id(1, _selected.id, _mouse_cell())
			# Consume the click so the player doesn't also fire their weapon.
			get_viewport().set_input_as_handled()
	elif _sell_mode:
		if event.is_action_pressed("build_cancel"):
			_set_sell_mode(false)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("build_confirm"):
			var cell := _mouse_cell()
			if _build_manager.building_at(cell) != null:
				_build_manager.request_sell.rpc_id(1, cell)
			# Consume the click even on open ground — you're holding the
			# hammer, not the bow.
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _selected != null:
		var cell := _mouse_cell()
		_ghost.position = _build_manager.cell_to_world(cell) + Vector3(0, 0.45, 0)
		var error := _build_manager.placement_error(
				_selected, cell, Network.local_player_class)
		_ghost_material.albedo_color = GHOST_VALID if error == "" else GHOST_INVALID
	elif _sell_mode:
		var building := _build_manager.building_at(_mouse_cell())
		_set_sell_hover(building)
		_ghost.visible = building != null
		if building != null:
			_ghost.position = _build_manager.cell_to_world(building.cell) \
					+ Vector3(0, 0.45, 0)
			_ghost_material.albedo_color = GHOST_SELL


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
