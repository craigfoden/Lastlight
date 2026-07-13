class_name Minimap
extends Control
## A corner radar centred on the local player. Shows nearby resource nodes in
## their material colour, monsters in red, teammates in cyan, and the direction
## home to the tower in gold (pinned to the rim when it is off-radar). Pure
## local rendering from the shared groups — reads state every peer already has,
## so it needs no networking of its own.

## World-space radius (pixels) the radar covers from centre to rim.
@export var world_range := 1000.0
@export var node_dot := 2.5
@export var enemy_dot := 3.0
@export var player_dot := 3.5

const _BACKING := Color(0.05, 0.06, 0.10, 0.72)
const _RIM := Color(1, 1, 1, 0.35)
const _ENEMY := Color(0.95, 0.3, 0.3)
const _MATE := Color(0.4, 0.85, 1.0)
const _SELF := Color(1, 1, 1)
const _TOWER := Color(1.0, 0.86, 0.4)

var _tower: GlowTower
var _player: Player


func setup(glow_tower: GlowTower) -> void:
	_tower = glow_tower


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = null
		for node in get_tree().get_nodes_in_group("players"):
			if node.is_multiplayer_authority():
				_player = node
				break
	visible = _player != null
	if visible:
		queue_redraw()


func _draw() -> void:
	if _player == null:
		return
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0
	var scale := radius / world_range
	var origin := _player.global_position

	draw_circle(center, radius, _BACKING)

	for node in get_tree().get_nodes_in_group("resource_nodes"):
		var res := node as ResourceNode
		if res == null or res.amount <= 0 or res.material_type == null:
			continue
		var rel: Vector2 = (res.global_position - origin) * scale
		if rel.length() <= radius:
			draw_circle(center + rel, node_dot, res.material_type.hud_color)

	for node in get_tree().get_nodes_in_group("enemies"):
		if node.hp <= 0:
			continue
		var rel: Vector2 = (node.global_position - origin) * scale
		if rel.length() <= radius:
			draw_circle(center + rel, enemy_dot, _ENEMY)

	for node in get_tree().get_nodes_in_group("players"):
		if node == _player:
			continue
		var rel: Vector2 = (node.global_position - origin) * scale
		if rel.length() <= radius:
			draw_circle(center + rel, player_dot, _MATE)

	# Home marker: pin the tower to the rim when it is off-radar so you can
	# always find your way back to the village.
	if _tower != null and is_instance_valid(_tower):
		var home: Vector2 = (_tower.global_position - origin) * scale
		if home.length() > radius:
			home = home.normalized() * radius
		draw_rect(Rect2(center + home - Vector2(3, 3), Vector2(6, 6)), _TOWER)

	draw_circle(center, player_dot, _SELF)
	draw_arc(center, radius, 0.0, TAU, 48, _RIM, 1.5)
