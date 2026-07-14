class_name Hud3D
extends CanvasLayer
## In-game overlay for the 3D port: day/phase clock, tower hp, shared material
## counts, player count, the local player's health + ability bar, the downed
## banner, and the "connecting" curtain a joining client sees. The 2D Hud could
## not be instanced untouched — it is statically typed to the 2D
## Player/GlowTower classes (see the decision log) — so this grows alongside
## the port instead: the minimap arrives with phase 7. Injection style matches
## the 2D Hud: the game scene hands us its nodes via setup(); we never reach
## into the tree for them. The minimap arrived with phase 7.

var _day_night: DayNightCycle
var _team_materials: TeamMaterials
var _glow_tower: GlowTower3D
var _material_labels := {}  # material id -> Label
var _local_player: Player3D

@onready var minimap: Minimap3D = %Minimap

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
		glow_tower: GlowTower3D) -> void:
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
				break
	ability_bar.visible = _local_player != null
	if _local_player == null:
		downed_banner.visible = false
		return
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
