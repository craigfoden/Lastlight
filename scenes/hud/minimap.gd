class_name Minimap
extends Control
## A corner radar centred on the local player — the 2D Minimap with a new
## world→radar transform: positions live on the XZ plane in cells, and the
## whole picture is rotated by the camera's fixed 45° yaw so up on the radar
## is up on the screen (in 2D the camera was axis-aligned and no rotation was
## needed). Shows nearby resource nodes in their material colour, monsters in
## red, teammates in cyan, landmarks as coloured diamonds, and the direction
## home to the tower in gold (pinned to the rim when it is off-radar). Pure
## local rendering from the shared groups — reads state every peer already has,
## so it needs no networking.
##
## Landmarks are the one thing on here you can also see out of the window
## (session 19), which is the point of drawing them: the radar is where you
## match the crag on your screen to the crag on the map and work out which way
## you are facing. Everything else on the radar is either too small to see at
## range or too far to see at all.

## World-space radius the radar covers from centre to rim, in cells
## (2D: 1000 px).
@export var world_range := 31.25
@export var node_dot := 2.5
@export var enemy_dot := 3.0
@export var player_dot := 3.5
## Radius of the ring drawn around a camp site.
@export var camp_ring := 6.5
## Half-diagonal of the diamond drawn at a landmark. A diamond rather than a
## dot or a ring so it cannot be read as either a resource node or a camp: the
## radar has three kinds of thing on it now and they must be three shapes.
@export var landmark_mark := 4.0

const _BACKING := Color(0.05, 0.06, 0.10, 0.72)
const _RIM := Color(1, 1, 1, 0.35)
const _ENEMY := Color(0.95, 0.3, 0.3)
const _MATE := Color(0.4, 0.85, 1.0)
const _SELF := Color(1, 1, 1)
const _TOWER := Color(1.0, 0.86, 0.4)
const _CAMP_HELD := Color(0.95, 0.45, 0.35, 0.85)
const _CAMP_OPEN := Color(0.55, 0.95, 0.6, 0.85)

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


# World offset from the local player -> radar offset from the radar centre:
# take the ground-plane components and rotate by the camera yaw so the radar
# matches what the screen shows.
func _to_radar(world_pos: Vector3, radar_scale: float) -> Vector2:
	var offset := world_pos - _player.global_position
	return Vector2(offset.x, offset.z) \
			.rotated(deg_to_rad(Player.CAMERA_YAW)) * radar_scale


func _draw() -> void:
	if _player == null:
		return
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0
	var radar_scale := radius / world_range

	draw_circle(center, radius, _BACKING)

	for node in get_tree().get_nodes_in_group("resource_nodes"):
		var res := node as ResourceNode
		if res == null or res.amount <= 0 or res.material_type == null:
			continue
		var rel := _to_radar(res.global_position, radar_scale)
		if rel.length() <= radius:
			draw_circle(center + rel, node_dot, res.material_type.hud_color)

	for node in get_tree().get_nodes_in_group("enemies"):
		if node.hp <= 0:
			continue
		var rel := _to_radar(node.global_position, radar_scale)
		if rel.length() <= radius:
			draw_circle(center + rel, enemy_dot, _ENEMY)

	for node in get_tree().get_nodes_in_group("players"):
		if node == _player:
			continue
		var rel := _to_radar(node.global_position, radar_scale)
		if rel.length() <= radius:
			draw_circle(center + rel, player_dot, _MATE)

	# Camp sites: a ring big enough to read as a place rather than a pickup.
	# Red while the garrison holds it, green once the cache is open — so a camp
	# you cleared and walked away from still says so when you come back for it.
	# `guards_remaining` is replicated, so a client's ring tells the truth.
	for node in get_tree().get_nodes_in_group("camps"):
		var camp := node as Camp
		if camp == null:
			continue
		var camp_rel := _to_radar(camp.global_position, radar_scale)
		if camp_rel.length() <= radius:
			draw_arc(center + camp_rel, camp_ring, 0.0, TAU, 20,
					_CAMP_OPEN if camp.is_cleared() else _CAMP_HELD, 1.5)

	# Landmarks, in their own colour. Drawn after the camps and before the home
	# marker so that where two things overlap, the one you steer by stays
	# legible. A landmark never changes state, so unlike a camp ring this is a
	# single colour with nothing to say beyond "there".
	for node in get_tree().get_nodes_in_group("landmarks"):
		var landmark := node as Landmark
		if landmark == null or landmark.type == null:
			continue
		var mark_rel := _to_radar(landmark.global_position, radar_scale)
		if mark_rel.length() > radius:
			continue
		var at := center + mark_rel
		draw_colored_polygon(PackedVector2Array([
				at + Vector2(0, -landmark_mark),
				at + Vector2(landmark_mark, 0),
				at + Vector2(0, landmark_mark),
				at + Vector2(-landmark_mark, 0)]),
				landmark.type.map_color)

	# Home marker: pin the tower to the rim when it is off-radar so you can
	# always find your way back to the village.
	if _tower != null and is_instance_valid(_tower):
		var home := _to_radar(_tower.global_position, radar_scale)
		if home.length() > radius:
			home = home.normalized() * radius
		draw_rect(Rect2(center + home - Vector2(3, 3), Vector2(6, 6)), _TOWER)

	draw_circle(center, player_dot, _SELF)
	draw_arc(center, radius, 0.0, TAU, 48, _RIM, 1.5)
