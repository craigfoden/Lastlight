class_name Hud3D
extends CanvasLayer
## Phase-4 slim HUD for the 3D port: shared material pool, player count, and
## the "connecting" curtain a joining client sees. The 2D Hud could not be
## instanced untouched — it is statically typed to the 2D Player/GlowTower
## classes (see the decision log) — so this grows alongside the port instead:
## day clock and tower hp arrive with phases 6-7, the ability bar with 6, the
## minimap with 7. Injection style matches the 2D Hud: the game scene hands us
## TeamMaterials via setup(); we never reach into the tree for it.

var _team_materials: TeamMaterials
var _material_labels := {}  # material id -> Label

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


func setup(team_materials: TeamMaterials) -> void:
	_team_materials = team_materials
	team_materials.pool_changed.connect(_refresh_materials)


func show_connecting(showing: bool) -> void:
	connecting_panel.visible = showing


func _refresh_materials() -> void:
	for material in Materials.ALL:
		var count := 0
		if _team_materials != null:
			count = _team_materials.count_of(material.id)
		_material_labels[material.id].text = "%s %d" % [material.display_name, count]


func _refresh_players() -> void:
	players_label.text = "Players: %d" % Network.player_count()
