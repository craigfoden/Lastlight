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

## Hint colours: selling, a legal upgrade, and a refused click. They match the
## ghost's own tints (BuildController.GHOST_SELL/UPGRADE/INVALID) so the text
## under the dock and the box on the ground always agree.
const HINT_SELL := Color(1.0, 0.75, 0.5)
const HINT_UPGRADE := Color(1.0, 0.85, 0.45)
const HINT_REFUSED := Color(1.0, 0.55, 0.55)

var _build_manager: BuildManager
var _build_controller: BuildController
var _team_materials: TeamMaterials
var _buttons := {}  # BuildingType -> Button
var _sell_button: Button
## Cell under the mouse, from BuildController. Slots are priced against it, so
## the bar answers "can I afford this *here*" rather than "can I afford this at
## full price on bare ground" — the two differ on every cell that already holds
## something, which since upgrades landed is most of the cells you click.
var _hover_cell := BuildController.CELL_NOWHERE

@onready var _slots: HBoxContainer = %Slots
@onready var _hint: Label = %Hint


## Injected by the Game scene.
func setup(
		build_manager: BuildManager,
		build_controller: BuildController,
		team_materials: TeamMaterials) -> void:
	_build_manager = build_manager
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
	build_controller.placement_preview_changed.connect(_on_placement_preview_changed)
	build_controller.hover_cell_changed.connect(_on_hover_cell_changed)
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
	_hint.visible = active
	_show_hint(SELL_HINT_DEFAULT, HINT_SELL)


# Promise exactly what the host will pay — both sides ask BuildingType.refund().
func _on_sell_hover_changed(building: Building) -> void:
	if building == null:
		_show_hint(SELL_HINT_DEFAULT, HINT_SELL)
		return
	var refund := building.type.refund()
	_show_hint("Sell %s — refunds %s" % [building.type.display_name,
			Materials.cost_text(refund) if not refund.is_empty() else "nothing"],
			HINT_SELL)


# Build mode: the hint only speaks up over a cell that already holds something,
# which is exactly when the click does something other than what the hotbar slot
# says. Quotes net_cost, so the promise is what the host will actually charge.
func _on_placement_preview_changed(
		type: BuildingType, cell: Vector2i, error: String) -> void:
	var existing := _build_manager.building_at(cell) if type != null else null
	if existing == null:
		_hint.visible = false
		return
	_hint.visible = true
	if error != "":
		_show_hint(error, HINT_REFUSED)
		return
	var verb := "Upgrade to" if existing.type.upgrades_to == type else "Replace with"
	var line := "%s %s — %s" % [verb, type.display_name,
			Materials.cost_text(_build_manager.net_cost(type, cell))]
	if type.attacks:
		line += " · %s" % _attack_text(type)
	_show_hint(line, HINT_UPGRADE)


func _show_hint(text: String, color: Color) -> void:
	_hint.text = text
	_hint.add_theme_color_override(&"font_color", color)


func _on_hover_cell_changed(cell: Vector2i) -> void:
	_hover_cell = cell
	_refresh_affordability()


# Priced at the hovered cell through the same `net_cost` the host charges, so a
# tower you can only afford because the wall under it refunds no longer looks
# unaffordable while placing perfectly well. The slot's *label* keeps quoting the
# gross cost — that is the building's price, and the discount belongs to the cell
# rather than to the slot; the hint under the dock spells out the netted number
# once you are actually holding that hammer.
func _refresh_affordability() -> void:
	for type in _buttons:
		_buttons[type].disabled = not _team_materials.can_afford(_price_at_hover(type))


# What a slot is priced at right now.
#
# Normally the netted cost at the hovered cell. The exception is a cell holding
# something this click could not replace — a tower already at its final tier, or
# simply another building in the way. `net_cost` still answers there (it prices
# the resolved building, which is whatever is already standing), and the answers
# it gives are misleading in both directions: a maxed tower greys its own slot on
# the top tier's full price, and a wall over a wall prices at nothing at all.
# Both cells refuse the click regardless, so pricing them as bare ground keeps
# the grey meaning exactly one thing: you cannot afford this building.
func _price_at_hover(type: BuildingType) -> Dictionary:
	var existing := _build_manager.building_at(_hover_cell)
	if existing != null:
		var placed := _build_manager.resolve_placement(type, _hover_cell)
		if _build_manager.replaceable_at(_hover_cell, placed) == null:
			return type.cost
	return _build_manager.net_cost(type, _hover_cell)


# Hover tooltip: the type's own description plus its stats, composed here so
# the .tres files never repeat their numbers in prose.
func _tooltip_for(type: BuildingType) -> String:
	var lines: Array[String] = []
	if type.description != "":
		lines.append(type.description)
	if type.attacks:
		lines.append(_attack_text(type))
	if type.class_id != &"":
		lines.append("%s exclusive." % String(type.class_id).capitalize())
	lines.append("Cost: %s · Sells back at %d%%" % [
			Materials.cost_text(type.cost), int(roundf(type.refund_fraction * 100.0))])
	# Spell out the upgrade line on the slot that starts it — otherwise nothing
	# in the UI tells you the higher tiers exist until you click one into being.
	var chain := type.upgrade_chain()
	if chain.size() > 1:
		lines.append("")
		lines.append("Upgrades in place — click this slot on one already built:")
		for i in range(1, chain.size()):
			var tier := chain[i]
			lines.append("  %s — %s · %s" % [
					tier.display_name, Materials.cost_text(tier.cost),
					_attack_text(tier)])
		lines.append("(you pay the difference — the old tier's refund comes off)")
	return "\n".join(lines)


func _attack_text(type: BuildingType) -> String:
	return "Damage %d · Range %.1f cells · Fires every %.1f s" % [
			type.damage, type.attack_range / PX_PER_UNIT, type.fire_interval]
