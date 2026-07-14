class_name Enemy3D
extends CharacterBody3D
## One monster in the 3D world. Host-simulated: the host runs pathfinding,
## movement, and attacks; clients receive position from the synchronizer and
## hp via RPC. Honors the group-"enemies" contract towers target:
## hp + host_take_damage() + host_send_snapshot().
##
## Port of the 2D Enemy (see scenes/enemy/enemy.gd): the same two behaviours
## share one body — ASSAULT monsters (night waves) path to the tower heart and
## batter the tower; ROAM monsters (daytime threats) wander the dark and chase
## any player who strays out of the safe zone. Paths come from the build grid
## as XZ waypoints (1 unit = 1 cell); the body floats pinned to y = 0.

## How this monster behaves. Set at spawn by the WaveDirector.
enum Behavior { ASSAULT, ROAM }

## 2D data resources stay px-denominated (32 px = 1 cell); convert at the
## boundary — speeds and ranges below divide by this once.
const PX_PER_UNIT := 32.0

## Roaming wander spread around the monster's home point (2D: 220 px).
@export var wander_radius := 6.875

var type: EnemyType
var behavior := Behavior.ASSAULT
var hp := 0:
	set(value):
		hp = value
		_update_appearance()

var _build_manager: BuildManager3D
var _tower: GlowTower3D
var _home := Vector3.ZERO
var _safe_radius := 0.0
var _path := PackedVector2Array()
var _path_index := 0
var _attack_cooldown := 0.0
var _root_remaining := 0.0
var _repath_cd := 0.0
var _wander_target := Vector3.ZERO
var _wander_pause := 0.0

@onready var _sprite: Sprite3D = $Sprite3D


## Called by the spawn function on every peer. The node refs are each peer's
## own local instances; only the host actually uses them.
func setup(
		new_type: EnemyType,
		start_position: Vector3,
		build_manager: BuildManager3D,
		tower: GlowTower3D,
		new_behavior := Behavior.ASSAULT,
		safe_radius := 0.0) -> void:
	type = new_type
	position = start_position
	_build_manager = build_manager
	_tower = tower
	behavior = new_behavior
	_home = start_position
	_safe_radius = safe_radius


func _ready() -> void:
	_sprite.texture = type.texture
	hp = type.max_hp
	if not multiplayer.is_server():
		set_physics_process(false)
		return
	# Mazes change under our feet; recompute whenever the grid does.
	_build_manager.grid_changed.connect(_repath)
	_repath()


func _physics_process(delta: float) -> void:
	if hp <= 0:
		return
	match behavior:
		Behavior.ROAM:
			_roam(delta)
		_:
			_assault(delta)


# Night waves: march to the tower heart and batter the tower.
func _assault(delta: float) -> void:
	if _tower.hp <= 0:
		return
	if global_position.distance_to(_tower.global_position) <= _attack_range():
		velocity = Vector3.ZERO
		_swing_at(delta, _tower)
		return
	if _root_remaining > 0.0:
		# Rooted: no walking (attacking, above, still works).
		_root_remaining -= delta
		velocity = Vector3.ZERO
		return
	if _path_index >= _path.size():
		_repath()
		if _path.is_empty():
			return
	_advance_path()


# Daytime threats: chase the nearest exposed player, else wander the dark.
func _roam(delta: float) -> void:
	var target := _nearest_target()
	if target != null and global_position.distance_to(target.global_position) <= _attack_range():
		velocity = Vector3.ZERO
		_swing_at(delta, target)
		return
	if _root_remaining > 0.0:
		_root_remaining -= delta
		velocity = Vector3.ZERO
		return
	if target != null:
		_repath_cd -= delta
		if _repath_cd <= 0.0 or _path_index >= _path.size():
			_path = _build_manager.path_to(global_position, target.global_position)
			_path_index = 0
			_repath_cd = 0.4
		_advance_path()
	else:
		_wander(delta)


# Nearest living player who is outside the safe zone (the village is a haven —
# monsters won't chase you home).
func _nearest_target() -> Player3D:
	var best: Player3D = null
	var aggro := type.aggro_range / PX_PER_UNIT
	var best_dist := aggro * aggro
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player3D
		if player == null or player.downed or player.hp <= 0:
			continue
		if _in_safe_zone(player.global_position):
			continue
		var dist := global_position.distance_squared_to(player.global_position)
		if dist < best_dist:
			best_dist = dist
			best = player
	return best


func _wander(delta: float) -> void:
	_wander_pause -= delta
	if _wander_pause > 0.0:
		velocity = Vector3.ZERO
		return
	if _path_index >= _path.size():
		_wander_target = _pick_wander_point()
		_path = _build_manager.path_to(global_position, _wander_target)
		_path_index = 0
		if _path.is_empty():
			_wander_pause = 0.6
			return
	_advance_path()
	if _path_index >= _path.size():
		_wander_pause = randf_range(0.6, 1.8)


func _pick_wander_point() -> Vector3:
	for _attempt in 6:
		var candidate := _home + Vector3(randf_range(1.25, wander_radius), 0, 0) \
				.rotated(Vector3.UP, randf() * TAU)
		if candidate.length() >= _safe_radius + 0.75:
			return candidate
	return _home


func _in_safe_zone(pos: Vector3) -> bool:
	return _safe_radius > 0.0 and pos.distance_to(_tower.global_position) < _safe_radius


func _swing_at(delta: float, victim: Object) -> void:
	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		_attack_cooldown = type.attack_interval
		victim.host_take_damage(type.damage)


func _advance_path() -> void:
	if _path_index >= _path.size():
		velocity = Vector3.ZERO
		return
	# Grid-plane waypoints (x, y) are world (x, 0, y) — see BuildManager3D.
	var waypoint := Vector3(_path[_path_index].x, 0.0, _path[_path_index].y)
	if global_position.distance_to(waypoint) < 0.1875:
		_path_index += 1
		return
	velocity = global_position.direction_to(waypoint) * (type.move_speed / PX_PER_UNIT)
	# Daytime roamers lurk in the dark and never set foot in the light: if this
	# step would cross into the safe zone, stop at its edge and drop the path
	# (a fresh one is picked next tick). ASSAULT monsters ignore this — the
	# night horde is meant to march through the village to the tower.
	if behavior == Behavior.ROAM and _safe_radius > 0.0:
		var next_pos := global_position + velocity * get_physics_process_delta_time()
		if _in_safe_zone(next_pos):
			velocity = Vector3.ZERO
			_path_index = _path.size()
			return
	move_and_slide()


## Host only: snare traps (and future crowd control) pin the enemy in place.
func host_apply_root(duration: float) -> void:
	if multiplayer.is_server():
		_root_remaining = maxf(_root_remaining, duration)


## Host only (towers and player shots call this).
func host_take_damage(amount: int) -> void:
	if not multiplayer.is_server() or hp <= 0:
		return
	var new_hp := maxi(hp - amount, 0)
	_sync_hp.rpc(new_hp)
	if new_hp == 0:
		print("[Enemy] %s (%s) died" % [name, type.id])
		# Freeing on the host despawns it on every peer via the spawner.
		queue_free()


## Host only: bring a late joiner up to date.
func host_send_snapshot(peer_id: int) -> void:
	_sync_hp.rpc_id(peer_id, hp)


func _repath() -> void:
	_path = _build_manager.path_to_heart(global_position)
	_path_index = 0


func _attack_range() -> float:
	return type.attack_range / PX_PER_UNIT


@rpc("authority", "call_local", "reliable")
func _sync_hp(new_hp: int) -> void:
	hp = new_hp


func _update_appearance() -> void:
	if _sprite == null:
		return
	_sprite.modulate.a = lerpf(0.4, 1.0, float(hp) / float(maxi(type.max_hp, 1)))
