class_name Hud
extends CanvasLayer
## In-game overlay: day/phase clock, shared material counts, player count,
## and the "connecting" curtain a joining client sees.
##
## The Game scene injects its DayNightCycle and TeamMaterials via setup() —
## the HUD never reaches into the tree to find them (dependency injection).

var _day_night: DayNightCycle
var _team_materials: TeamMaterials
var _glow_tower: GlowTower
var _material_labels := {}  # material id -> Label

@onready var day_label: Label = %DayLabel
@onready var clock_label: Label = %ClockLabel
@onready var tower_label: Label = %TowerLabel
@onready var foes_label: Label = %FoesLabel
@onready var players_label: Label = %PlayersLabel
@onready var materials_row: HBoxContainer = %MaterialsRow
@onready var connecting_panel: Control = %ConnectingPanel


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


func _refresh_materials() -> void:
	for material in Materials.ALL:
		var count := 0
		if _team_materials != null:
			count = _team_materials.count_of(material.id)
		_material_labels[material.id].text = "%s %d" % [material.display_name, count]


func _refresh_players() -> void:
	players_label.text = "Players: %d" % Network.player_count()
