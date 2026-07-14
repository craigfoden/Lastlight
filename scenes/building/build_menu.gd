class_name BuildMenu
extends CanvasLayer
## Bottom hotbar for the 3D game: one slot per buildable type showing hotkey,
## name, and cost. Purely a view over BuildController/TeamMaterials —
## clicking a slot is the same as pressing its hotkey. A parallel port of the
## 2D BuildMenu (which is typed to the 2D build classes); it retires with the
## rest of the 2D scenes at phase 8.

var _build_controller: BuildController
var _team_materials: TeamMaterials
var _buttons := {}  # BuildingType -> Button

@onready var _slots: HBoxContainer = %Slots


## Injected by the Game scene.
func setup(
		build_manager: BuildManager,
		build_controller: BuildController,
		team_materials: TeamMaterials) -> void:
	_build_controller = build_controller
	_team_materials = team_materials

	for i in build_manager.buildable_types.size():
		var type := build_manager.buildable_types[i]
		var button := Button.new()
		button.toggle_mode = true
		button.text = "[%d] %s\n%s" % [i + 1, type.display_name, Materials.cost_text(type.cost)]
		button.pressed.connect(_on_slot_pressed.bind(type))
		_slots.add_child(button)
		_buttons[type] = button

	build_controller.selection_changed.connect(_on_selection_changed)
	team_materials.pool_changed.connect(_refresh_affordability)
	_refresh_affordability()


func _on_slot_pressed(type: BuildingType) -> void:
	# The controller is the single owner of selection state; it signals back.
	_build_controller.toggle(type)


func _on_selection_changed(selected: BuildingType) -> void:
	for type in _buttons:
		_buttons[type].set_pressed_no_signal(type == selected)


func _refresh_affordability() -> void:
	for type in _buttons:
		_buttons[type].disabled = not _team_materials.can_afford(type.cost)
