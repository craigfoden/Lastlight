extends Control
## Class-select screen: sits between the main menu and the game scene, and is
## the one place `Network.local_player_class` is set. Picking here (rather than
## in-game) means the choice is in the roster from the first packet, so the
## host can spawn the right character without a second round trip.
##
## Every card is built from `Classes.ALL` at runtime — adding a class is still
## a .tres file and a preload, with no scene edit.
##
## Scripted runs never reach this screen: `--host` / `--join` on the main menu
## go straight to the game and read `--class=<id>` instead (see main_menu.gd).

const GAME_SCENE := "res://scenes/game/game.tscn"
const MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"

## Ability data is px-denominated; the screen shows cells, like the HUD does.
const PX_PER_UNIT := 32.0

var _selected: ClassType
var _buttons := {}  # ClassType -> Button

@onready var _cards: HBoxContainer = %Cards
@onready var _detail_name: Label = %DetailName
@onready var _detail_body: RichTextLabel = %DetailBody
@onready var _portrait: TextureRect = %Portrait


func _ready() -> void:
	for class_type in Classes.ALL:
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(150, 0)
		button.text = class_type.display_name
		button.pressed.connect(_select.bind(class_type))
		_cards.add_child(button)
		_buttons[class_type] = button
	%ConfirmButton.pressed.connect(_confirm)
	%BackButton.pressed.connect(_go_back)
	# Come back to this screen and your last pick is still highlighted.
	_select(Classes.by_id(Network.local_player_class))


func _select(class_type: ClassType) -> void:
	_selected = class_type
	for candidate in _buttons:
		_buttons[candidate].button_pressed = candidate == class_type
	_portrait.texture = class_type.sprite
	_detail_name.text = class_type.display_name
	_detail_body.text = _describe(class_type)


func _describe(class_type: ClassType) -> String:
	var lines: Array[String] = []
	if class_type.description != "":
		lines.append(class_type.description + "\n")
	lines.append("[b]%d[/b] health   ·   [b]%.1f[/b] cells/s   ·   dodge every [b]%.1f s[/b]\n"
			% [class_type.max_hp, class_type.move_speed / PX_PER_UNIT,
			class_type.dodge_cooldown])
	for pair in [["LMB", class_type.basic_attack], ["Q", class_type.ability_1],
			["F", class_type.ability_2]]:
		var ability: AbilityType = pair[1]
		if ability == null:
			continue
		lines.append("[b]%s — %s[/b]  (%s)" % [pair[0], ability.display_name,
				_ability_stats(ability)])
		if ability.description != "":
			lines.append("[i]%s[/i]\n" % ability.description)
	return "\n".join(lines)


# Composed from the same fields the game runs on, so the screen cannot promise
# something the ability does not do (the tooltip rule from session 10).
func _ability_stats(ability: AbilityType) -> String:
	match ability.kind:
		AbilityType.Kind.PROJECTILE:
			return "%d damage, %.1f cells, every %.2f s" % [ability.damage,
					ability.projectile_range / PX_PER_UNIT, ability.cooldown]
		AbilityType.Kind.DEPLOYABLE:
			var effect := "roots %.1f s" % ability.root_duration if ability.root_duration > 0.0 \
					else "burns %d every %.1f s for %.0f s" % [ability.tick_damage,
					ability.tick_interval, ability.lifetime]
			return "%s, every %.0f s" % [effect, ability.cooldown]
		AbilityType.Kind.MELEE_ARC:
			var shape := "all around you" if ability.arc_degrees >= 360.0 \
					else "%.0f° arc" % ability.arc_degrees
			var held := ", roots %.1f s" % ability.root_duration \
					if ability.root_duration > 0.0 else ""
			return "%d damage, %.1f cells, %s%s, every %.2f s" % [ability.damage,
					ability.melee_range / PX_PER_UNIT, shape, held, ability.cooldown]
		AbilityType.Kind.SELF_BUFF:
			return "%.0f%% less damage for %.0f s, every %.0f s" % [
					ability.damage_reduction * 100.0, ability.buff_duration, ability.cooldown]
	return "every %.2f s" % ability.cooldown


func _confirm() -> void:
	Network.local_player_class = _selected.id
	print("[Menu] Class chosen: %s" % _selected.id)
	get_tree().change_scene_to_file(GAME_SCENE)


func _go_back() -> void:
	# The menu will set start_mode again when they pick Host or Join.
	Network.start_mode = Network.StartMode.NONE
	get_tree().change_scene_to_file(MENU_SCENE)
