class_name Hud
extends CanvasLayer
## In-game overlay: day/phase clock, tower hp, shared material counts, player
## count, the local player's health + ability bar, the downed banner, the
## corner minimap, and the "connecting" curtain a joining client sees.
##
## The Game scene injects its nodes via setup() — the HUD never reaches into
## the tree to find them (dependency injection).

## .tres stats are px-denominated; tooltips show cells (1 cell = 32 px of 2D-era art).
const PX_PER_UNIT := 32.0

var _day_night: DayNightCycle
var _team_materials: TeamMaterials
var _glow_tower: GlowTower
var _material_labels := {}  # material id -> Label
var _local_player: Player

@onready var minimap: Minimap = %Minimap

@onready var day_label: Label = %DayLabel
@onready var clock_label: Label = %ClockLabel
@onready var tower_label: Label = %TowerLabel
@onready var foes_label: Label = %FoesLabel
@onready var players_label: Label = %PlayersLabel
@onready var materials_row: HBoxContainer = %MaterialsRow
@onready var connecting_panel: Control = %ConnectingPanel
@onready var ability_bar: Control = %AbilityBar
@onready var health_label: Label = %HealthLabel
@onready var downed_banner: Label = %DownedBanner
@onready var attack_label: Label = %AttackLabel
@onready var ability_1_label: Label = %Ability1Label
@onready var ability_2_label: Label = %Ability2Label
@onready var dodge_label: Label = %DodgeLabel
@onready var interact_hint: Label = %InteractHint


func _ready() -> void:
	for material in Materials.ALL:
		var label := Label.new()
		label.self_modulate = material.hud_color
		materials_row.add_child(label)
		_material_labels[material.id] = label
	Network.player_list_changed.connect(_refresh_players)
	_refresh_materials()
	_refresh_players()


func setup(
		day_night: DayNightCycle,
		team_materials: TeamMaterials,
		glow_tower: GlowTower) -> void:
	_day_night = day_night
	_team_materials = team_materials
	_glow_tower = glow_tower
	team_materials.pool_changed.connect(_refresh_materials)
	minimap.setup(glow_tower)


func show_connecting(showing: bool) -> void:
	connecting_panel.visible = showing


func _process(_delta: float) -> void:
	if _day_night == null:
		return
	day_label.text = "Day %d / %d" % [_day_night.day_number, _day_night.final_day]
	var remaining := int(ceilf(_day_night.time_remaining()))
	var phase_name := "Daylight" if _day_night.phase == DayNightCycle.Phase.DAY else "NIGHT"
	clock_label.text = "%s  %d:%02d" % [phase_name, remaining / 60, remaining % 60]
	tower_label.text = "Tower %d/%d" % [_glow_tower.hp, _glow_tower.max_hp]
	var low := _glow_tower.hp <= _glow_tower.max_hp * 0.3
	tower_label.self_modulate = Color(1, 0.45, 0.45) if low else Color.WHITE
	var foes := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.hp > 0:
			foes += 1
	foes_label.text = "Foes: %d" % foes
	foes_label.visible = foes > 0
	_refresh_ability_bar()


func _refresh_ability_bar() -> void:
	if _local_player == null or not is_instance_valid(_local_player):
		_local_player = null
		for node in get_tree().get_nodes_in_group("players"):
			if node.is_multiplayer_authority():
				_local_player = node
				_configure_ability_tooltips()
				break
	ability_bar.visible = _local_player != null
	if _local_player == null:
		downed_banner.visible = false
		interact_hint.visible = false
		return
	_refresh_interact_hint()
	health_label.text = "HP %d/%d" % [_local_player.hp, _local_player.max_hp]
	var low := _local_player.hp <= _local_player.max_hp * 0.3
	health_label.self_modulate = Color(1, 0.45, 0.45) if low else Color.WHITE
	downed_banner.visible = _local_player.downed
	if _local_player.downed:
		downed_banner.text = "DOWNED\nA teammate can revive you — or the village will call you back."
	var class_type := _local_player.class_type
	_set_slot(attack_label, "LMB", class_type.basic_attack,
			_local_player.cooldown_remaining(class_type.basic_attack))
	_set_slot(ability_1_label, "Q", class_type.ability_1,
			_local_player.cooldown_remaining(class_type.ability_1))
	_set_slot(ability_2_label, "F", class_type.ability_2,
			_local_player.cooldown_remaining(class_type.ability_2))
	var dodge_cd := _local_player.dodge_cooldown_remaining()
	dodge_label.text = "SPC Dodge Roll" if dodge_cd <= 0.0 \
			else "SPC Dodge Roll  %.1f" % dodge_cd


# Hover tooltips for the ability bar, set once the local player (and so their
# class) is known. Labels ignore the mouse by default; PASS lets them show a
# tooltip without swallowing clicks.
func _configure_ability_tooltips() -> void:
	var class_type := _local_player.class_type
	for pair in [[attack_label, class_type.basic_attack],
			[ability_1_label, class_type.ability_1], [ability_2_label, class_type.ability_2]]:
		var label: Label = pair[0]
		var ability: AbilityType = pair[1]
		if ability == null:
			continue
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.tooltip_text = _ability_tooltip(ability)
	dodge_label.mouse_filter = Control.MOUSE_FILTER_PASS
	var roll_cells := (class_type.dodge_speed / PX_PER_UNIT) * class_type.dodge_duration
	dodge_label.tooltip_text = ("A quick burst in your movement direction "
			+ "(aim direction when standing still).\n"
			+ "Distance %.1f cells · Cooldown %.1f s"
			% [roll_cells, class_type.dodge_cooldown])


func _ability_tooltip(ability: AbilityType) -> String:
	var lines: Array[String] = []
	if ability.description != "":
		lines.append(ability.description)
	match ability.kind:
		AbilityType.Kind.PROJECTILE:
			lines.append("Damage %d · Range %.1f cells" % [
					ability.damage, ability.projectile_range / PX_PER_UNIT])
		AbilityType.Kind.DEPLOYABLE:
			var parts: Array[String] = []
			if ability.root_duration > 0.0:
				parts.append("Roots for %.1f s" % ability.root_duration)
			if ability.tick_damage > 0:
				parts.append("Burns %d every %.1f s" % [
						ability.tick_damage, ability.tick_interval])
			parts.append("Lasts %.0f s on the ground" % ability.lifetime)
			lines.append(" · ".join(parts))
		AbilityType.Kind.MELEE_ARC:
			var shape := "All around you" if ability.arc_degrees >= 360.0 \
					else "%.0f° arc" % ability.arc_degrees
			var arc_line := "Damage %d · Reach %.1f cells · %s" % [
					ability.damage, ability.melee_range / PX_PER_UNIT, shape]
			if ability.root_duration > 0.0:
				arc_line += " · Roots for %.1f s" % ability.root_duration
			lines.append(arc_line)
		AbilityType.Kind.SELF_BUFF:
			lines.append("Takes %d%% less damage for %.0f s" % [
					int(roundf(ability.damage_reduction * 100.0)), ability.buff_duration])
	lines.append("Cooldown %.2f s" % ability.cooldown)
	return "\n".join(lines)


# "E  Chop Wood (3 left → 4)" over the hotbar whenever pressing E would actually
# land — same nearest_harvestable() the harvest itself uses, so the prompt never
# lies. The chop count and payout are both shown because nothing is paid until
# the node falls: without it, a 14-chop tree reads as broken.
func _refresh_interact_hint() -> void:
	var target := _local_player.nearest_harvestable() if not _local_player.downed else null
	interact_hint.visible = target != null
	if target != null:
		interact_hint.text = "E  Chop %s  (%d left → %d)" % [
				target.material_type.display_name, target.amount, target.depleted_yield]


func _set_slot(label: Label, key: String, ability: AbilityType, cd: float) -> void:
	if ability == null:
		label.visible = false
		return
	label.text = "%s %s" % [key, ability.display_name] if cd <= 0.0 \
			else "%s %s  %.1f" % [key, ability.display_name, cd]
	label.self_modulate = Color.WHITE if cd <= 0.0 else Color(1, 1, 1, 0.45)


func _refresh_materials() -> void:
	for material in Materials.ALL:
		var count := 0
		if _team_materials != null:
			count = _team_materials.count_of(material.id)
		_material_labels[material.id].text = "%s %d" % [material.display_name, count]


func _refresh_players() -> void:
	players_label.text = "Players: %d" % Network.player_count()
