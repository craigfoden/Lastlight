class_name BuildMenu
extends CanvasLayer
## Bottom hotbar for the 3D game: one slot per buildable type showing hotkey,
## name, and cost, plus the [X] Sell toggle and its hover hint. Purely a view
## over BuildController/TeamMaterials — clicking a slot is the same as
## pressing its hotkey.

## .tres stats are px-denominated; UI shows cells (1 cell = 32 px of 2D-era art).
const PX_PER_UNIT := 32.0

## Shown while sell mode is on but nothing removable is under the mouse.
const SELL_HINT_DEFAULT := "Click a highlighted building to sell it"

var _build_controller: BuildController
var _team_materials: TeamMaterials
var _buttons := {}  # BuildingType -> Button
var _sell_button: Button

@onready var _slots: HBoxContainer = %Slots
@onready var _sell_hint: Label = %SellHint


## Injected by the Game scene.
func setup(
		build_manager: BuildManager,
		build_controller: BuildController,
		team_materials: TeamMaterials) -> void:
	_build_controller = build_controller
	_team_materials = team_materials

	# Only what this player's class can actually place — an exclusive tower in
	# someone else's hotbar is a slot that always refuses.
	var my_types := build_manager.types_for_class(Network.local_player_class)
	for i in my_types.size():
		var type := my_types[i]
		var button := Button.new()
		button.toggle_mode = true
		button.text = "[%d] %s\n%s" % [i + 1, type.display_name, Materials.cost_text(type.cost)]
		button.tooltip_text = _tooltip_for(type)
		button.pressed.connect(_on_slot_pressed.bind(type))
		_slots.add_child(button)
		_buttons[type] = button

	_sell_button = Button.new()
	_sell_button.toggle_mode = true
	_sell_button.text = "[X] Sell"
	_sell_button.tooltip_text = ("Remove a building and refund materials — "
			+ "walls in full, towers at half.\nHover a building and click to "
			+ "sell; Esc or X puts the hammer away.")
	_sell_button.pressed.connect(build_controller.toggle_sell_mode)
	_slots.add_child(_sell_button)

	build_controller.selection_changed.connect(_on_selection_changed)
	build_controller.sell_mode_changed.connect(_on_sell_mode_changed)
	build_controller.sell_hover_changed.connect(_on_sell_hover_changed)
	team_materials.pool_changed.connect(_refresh_affordability)
	_refresh_affordability()


func _on_slot_pressed(type: BuildingType) -> void:
	# The controller is the single owner of selection state; it signals back.
	_build_controller.toggle(type)


func _on_selection_changed(selected: BuildingType) -> void:
	for type in _buttons:
		_buttons[type].set_pressed_no_signal(type == selected)


func _on_sell_mode_changed(active: bool) -> void:
	_sell_button.set_pressed_no_signal(active)
	_sell_hint.visible = active
	_sell_hint.text = SELL_HINT_DEFAULT


# Promise exactly what the host will pay — both sides ask BuildingType.refund().
func _on_sell_hover_changed(building: Building) -> void:
	if building == null:
		_sell_hint.text = SELL_HINT_DEFAULT
		return
	var refund := building.type.refund()
	_sell_hint.text = "Sell %s — refunds %s" % [building.type.display_name,
			Materials.cost_text(refund) if not refund.is_empty() else "nothing"]


func _refresh_affordability() -> void:
	for type in _buttons:
		_buttons[type].disabled = not _team_materials.can_afford(type.cost)


# Hover tooltip: the type's own description plus its stats, composed here so
# the .tres files never repeat their numbers in prose.
func _tooltip_for(type: BuildingType) -> String:
	var lines: Array[String] = []
	if type.description != "":
		lines.append(type.description)
	if type.attacks:
		lines.append("Damage %d · Range %.1f cells · Fires every %.1f s" % [
				type.damage, type.attack_range / PX_PER_UNIT, type.fire_interval])
	if type.class_id != &"":
		lines.append("%s exclusive." % String(type.class_id).capitalize())
	lines.append("Cost: %s · Sells back at %d%%" % [
			Materials.cost_text(type.cost), int(roundf(type.refund_fraction * 100.0))])
	return "\n".join(lines)
