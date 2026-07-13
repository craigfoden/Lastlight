class_name BuildController
extends Node2D
## Local-only build input: hotbar selection, the snapped ghost preview, and
## sending place/sell requests to the host. Never mutates game state itself —
## every action goes through BuildManager's host-validated RPCs.
##
## Mouse + keyboard for now; gamepad build placement is a logged roadmap gap.

signal selection_changed(type: BuildingType)

const GHOST_VALID := Color(0.55, 1.0, 0.55, 0.6)
const GHOST_INVALID := Color(1.0, 0.4, 0.4, 0.6)

var _build_manager: BuildManager
var _selected: BuildingType

@onready var _ghost: Sprite2D = $Ghost


## Injected by the Game scene.
func setup(build_manager: BuildManager) -> void:
	_build_manager = build_manager


## Select if it isn't selected; put the hammer away if it is.
func toggle(type: BuildingType) -> void:
	select(null if type == _selected else type)


func select(type: BuildingType) -> void:
	_selected = type
	_ghost.visible = type != null
	if type != null:
		_ghost.texture = type.texture
		# Preview exactly where the sprite will stand (shared baseline anchor).
		SpriteAnchor.apply(_ghost)
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
	_ghost.global_position = _build_manager.cell_to_world(cell)
	var error := _build_manager.placement_error(
			_selected, cell, Network.local_player_class)
	_ghost.modulate = GHOST_VALID if error == "" else GHOST_INVALID


func _mouse_cell() -> Vector2i:
	return _build_manager.world_to_cell(get_global_mouse_position())
