class_name Building
extends StaticBody3D
## A placed structure (wall or tower) in the 3D world. Every peer builds an
## identical node from replicated spawn data; only the host runs targeting and
## applies damage. Shot visuals are cosmetic and drawn locally on each peer —
## same contract as the 2D Building.
##
## Since session 18 a building can also be *taken down*: it keeps hp, and
## anything hostile can swing at it through `host_take_damage`. The hp lane is
## the same one the tower and every enemy use — host decides, `_sync_hp`
## broadcasts, the setter drives the look on every peer. Falling is just
## `queue_free()` on the host: the spawner despawns it everywhere and
## BuildManager's child-exiting hook frees the cell and repaths whatever was
## walking, with no extra sync at all.

## 2D data is px-denominated; convert at the boundary (1 unit = 1 cell = 32 px).
const PX_PER_UNIT := 32.0

## World units per second for the cosmetic shot mesh (2D: 500 px/s).
const SHOT_SPEED := 500.0 / PX_PER_UNIT

var type: BuildingType
var cell: Vector2i

var hp := 0:
	set(value):
		hp = value
		_update_appearance()

var _visual: Node3D

@onready var _fire_timer: Timer = $FireTimer


## Called by the spawn function before entering the tree.
func setup(new_type: BuildingType, new_cell: Vector2i) -> void:
	type = new_type
	cell = new_cell


func _ready() -> void:
	print("[Building] %s at %s" % [type.id, cell])
	if type.visual_3d != null:
		_visual = type.visual_3d.instantiate() as Node3D
		add_child(_visual)
	hp = type.max_hp
	if type.attacks and multiplayer.is_server():
		_fire_timer.wait_time = type.fire_interval
		_fire_timer.timeout.connect(_host_fire)
		_fire_timer.start()


# Host only: pick a target, apply damage, tell everyone to draw the shot.
func _host_fire() -> void:
	var target := _nearest_living_enemy()
	if target == null:
		return
	target.host_take_damage(type.damage)
	_show_shot.rpc(target.global_position)


func _nearest_living_enemy() -> Node3D:
	var best: Node3D = null
	var best_range := type.attack_range / PX_PER_UNIT
	var best_dist := best_range * best_range
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.hp <= 0:
			continue
		var dist: float = global_position.distance_squared_to(enemy.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = enemy
	return best


## Host only: enemies that have given up on walking round swing at us through
## here (the same entry point the tower has). The node's authority is the
## server, so a plain-"authority" broadcast is correct — unlike anything hanging
## off a player node (see GOTCHAS).
func host_take_damage(amount: int) -> void:
	if not multiplayer.is_server() or hp <= 0:
		return
	var new_hp := maxi(hp - amount, 0)
	_sync_hp.rpc(new_hp)
	if new_hp == 0:
		print("[Building] %s at %s was destroyed" % [type.id, cell])
		# Freeing on the host despawns it on every peer through the spawner, and
		# BuildManager frees the cell and emits grid_changed off the exiting-tree
		# hook — so nothing else has to be told.
		queue_free()


## Host only: bring a late joiner up to date. The building itself is replayed by
## its spawner, but the damage it has taken since is ours to send.
func host_send_snapshot(peer_id: int) -> void:
	_sync_hp.rpc_id(peer_id, hp)


@rpc("authority", "call_local", "reliable")
func _sync_hp(new_hp: int) -> void:
	hp = new_hp


# A structure being battered leans toward its ruin colour and settles lower on
# its cell — readable at a glance from across the village, and it costs nothing
# to replicate because hp already is.
func _update_appearance() -> void:
	if _visual == null or type == null:
		return
	var fraction := clampf(float(hp) / float(maxi(type.max_hp, 1)), 0.0, 1.0)
	_visual.scale = Vector3(1.0, lerpf(0.72, 1.0, fraction), 1.0)


# Cosmetic only — the host already applied the damage.
@rpc("authority", "call_local", "unreliable")
func _show_shot(target_pos: Vector3) -> void:
	var shot := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.12, 0.35)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.55)
	mesh.material = mat
	shot.mesh = mesh
	shot.top_level = true
	add_child(shot)
	var from := global_position + Vector3(0, 1.2, 0)
	shot.global_position = from
	# Aim along the horizontal direction only — a straight-down look_at would
	# align with the up vector and error.
	var flat_target := Vector3(target_pos.x, from.y, target_pos.z)
	if from.distance_to(flat_target) > 0.01:
		shot.look_at(flat_target)
	var tween := shot.create_tween()
	var flight_time := from.distance_to(target_pos) / SHOT_SPEED
	tween.tween_property(shot, "global_position", target_pos, flight_time)
	tween.tween_callback(shot.queue_free)
