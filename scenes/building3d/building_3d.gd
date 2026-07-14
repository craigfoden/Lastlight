class_name Building3D
extends StaticBody3D
## A placed structure (wall or tower) in the 3D world. Every peer builds an
## identical node from replicated spawn data; only the host runs targeting and
## applies damage. Shot visuals are cosmetic and drawn locally on each peer —
## same contract as the 2D Building.

## 2D data is px-denominated; convert at the boundary (1 unit = 1 cell = 32 px).
const PX_PER_UNIT := 32.0

## World units per second for the cosmetic shot mesh (2D: 500 px/s).
const SHOT_SPEED := 500.0 / PX_PER_UNIT

var type: BuildingType
var cell: Vector2i

@onready var _fire_timer: Timer = $FireTimer


## Called by the spawn function before entering the tree.
func setup(new_type: BuildingType, new_cell: Vector2i) -> void:
	type = new_type
	cell = new_cell


func _ready() -> void:
	print("[Building] %s at %s" % [type.id, cell])
	if type.visual_3d != null:
		add_child(type.visual_3d.instantiate())
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
