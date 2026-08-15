class_name Enemy
extends CharacterBody3D
## One monster in the 3D world. Host-simulated: the host runs pathfinding,
## movement, and attacks; clients receive position from the synchronizer and
## hp via RPC. Honors the group-"enemies" contract towers target:
## hp + host_take_damage() + host_send_snapshot().
##
## Three behaviours share one body — ASSAULT monsters (night waves) path to the tower heart and
## batter the tower; ROAM monsters (daytime threats) wander the dark and chase
## any player who strays out of the safe zone; GUARD monsters hold a camp,
## chasing only to the end of a leash before walking back to their post. A
## roamer alive at nightfall is switched to ASSAULT by the WaveDirector
## (`host_join_assault`), so the day's leftovers march with the horde — guards
## are exempt, or a camp would clear itself overnight. Paths come from the build
## grid as XZ waypoints (1 unit = 1 cell); the body floats pinned to y = 0.

## How this monster behaves. Set at spawn by the WaveDirector. Append-only —
## the value travels in spawn packets.
enum Behavior { ASSAULT, ROAM, GUARD }

## Host only: this monster was killed (as opposed to despawned at dawn or at
## run end). Camps count their garrison down on this, so a wipe-the-field
## despawn can never read as "the players cleared it".
signal died

## 2D data resources stay px-denominated (32 px = 1 cell); convert at the
## boundary — speeds and ranges below divide by this once.
const PX_PER_UNIT := 32.0

## One leg of a roamer's stroll, in cells: shortest and longest it will walk
## before picking a new heading (2D: 220 px was the old spread).
@export var wander_step_min := 3.0
@export var wander_radius := 6.875
## Clearance kept between a wander destination and the safe zone's edge. Points
## are rejected inside it, so a roamer never *aims* at a cell the light will
## refuse to let it enter — that mismatch is what used to park them on the edge.
@export var wander_light_margin := 2.0
## How close to its post a returning guard has to get before it counts as home
## again, in cells. Doubles as the hysteresis that stops a guard oscillating on
## its leash boundary — it must come all the way back before it will chase again.
@export var guard_post_tolerance := 0.75

var type: EnemyType
var behavior := Behavior.ASSAULT
var hp := 0:
	set(value):
		hp = value
		_update_appearance()

var _build_manager: BuildManager
var _tower: GlowTower
var _safe_radius := 0.0
## Outer leash for roaming, in cells (0 = none) — WaveDirector's roamer ring.
var _roam_max_radius := 0.0
## Set by _advance_path when the light turned this roamer back, so the wander
## can abandon that leg and head outward instead of pressing on the edge.
var _light_blocked := false
var _path := PackedVector2Array()
var _path_index := 0
var _attack_cooldown := 0.0
var _root_remaining := 0.0
var _repath_cd := 0.0
var _wander_target := Vector3.ZERO
var _wander_pause := 0.0
## GUARD only: the post this monster holds, and how far it will stray from it.
var _home := Vector3.ZERO
var _leash := 0.0
## GUARD only: walking back to its post, and refusing to chase until it arrives.
var _returning := false
var _light_tint := Color.WHITE  # day/night tint, driven by WorldLight

@onready var _sprite: Sprite3D = $Sprite3D


## Called by the spawn function on every peer. The node refs are each peer's
## own local instances; only the host actually uses them.
func setup(
		new_type: EnemyType,
		start_position: Vector3,
		build_manager: BuildManager,
		tower: GlowTower,
		new_behavior := Behavior.ASSAULT,
		safe_radius := 0.0,
		roam_max_radius := 0.0,
		home := Vector3.ZERO,
		leash := 0.0) -> void:
	type = new_type
	position = start_position
	_build_manager = build_manager
	_tower = tower
	behavior = new_behavior
	_safe_radius = safe_radius
	_roam_max_radius = roam_max_radius
	_home = home
	_leash = leash


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
		Behavior.GUARD:
			_guard(delta)
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
		# A chase that ran into the light is just a chase that ended; don't let
		# the flag leak into the next wander leg.
		_light_blocked = false
	else:
		_wander(delta)


# Camp garrison: hold the site. Fights anything that comes to it, chases only
# to the end of its leash, then walks back to its post. The leash is what keeps
# a camp a place instead of a pull: back away far enough and you have taken one
# guard for a walk, not emptied the courtyard — but you can never kite the
# garrison off the map and stroll in to the cache.
func _guard(delta: float) -> void:
	var target := _nearest_target()
	if target != null and global_position.distance_to(target.global_position) <= _attack_range():
		velocity = Vector3.ZERO
		_swing_at(delta, target)
		return
	if _root_remaining > 0.0:
		_root_remaining -= delta
		velocity = Vector3.ZERO
		return
	var home_dist := global_position.distance_to(_home)
	if _leash > 0.0 and home_dist >= _leash:
		_returning = true
	if _returning and home_dist <= guard_post_tolerance:
		_returning = false
	if target != null and not _returning:
		_repath_cd -= delta
		if _repath_cd <= 0.0 or _path_index >= _path.size():
			_path = _build_manager.path_to(global_position, target.global_position)
			_path_index = 0
			_repath_cd = 0.4
		_advance_path()
		# Same as ROAM: a chase that ran into the light is just a chase that ended.
		_light_blocked = false
		return
	if home_dist > guard_post_tolerance:
		if _path_index >= _path.size():
			_path = _build_manager.path_to(global_position, _home)
			_path_index = 0
		_advance_path()
		return
	# At its post with nothing to fight: stand.
	velocity = Vector3.ZERO


# Nearest living player who is outside the safe zone (the village is a haven —
# monsters won't chase you home).
func _nearest_target() -> Player:
	var best: Player = null
	var aggro := type.aggro_range / PX_PER_UNIT
	var best_dist := aggro * aggro
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
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
		_wander_target = _pick_wander_point(_light_blocked)
		_light_blocked = false
		_path = _build_manager.path_to(global_position, _wander_target)
		_path_index = 0
		if _path.is_empty():
			_wander_pause = 0.6
			return
	_advance_path()
	if _light_blocked:
		# The path we were handed cut through the light. Abandon this leg now and
		# pick an outward one next tick — never stand around on the edge. The
		# short pause is a busy-loop guard, not a rest.
		_path_index = _path.size()
		_wander_pause = 0.15
		return
	if _path_index >= _path.size():
		_wander_pause = randf_range(0.6, 1.8)


# Somewhere to stroll next, sampled around where the monster actually is (not a
# fixed spawn anchor — roamers that chased a player should carry on from there).
# `outward` biases the heading away from the tower, used when the light just
# turned us back.
func _pick_wander_point(outward: bool) -> Vector3:
	var from_tower := global_position - _tower.global_position
	var outward_dir := from_tower.normalized() if from_tower.length() > 0.01 \
			else Vector3.FORWARD
	for _attempt in 8:
		var direction := outward_dir.rotated(Vector3.UP, randf_range(-PI / 3.0, PI / 3.0)) \
				if outward else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		var candidate := global_position \
				+ direction * randf_range(wander_step_min, wander_radius)
		if _accepts_wander_point(candidate):
			return candidate
	# Nothing sampled clean (pinned in a corner or hugging the light): step
	# straight out from the tower, which is always away from the edge.
	return global_position + outward_dir * wander_step_min


func _accepts_wander_point(point: Vector3) -> bool:
	var from_tower := point.distance_to(_tower.global_position)
	if from_tower < _safe_radius + wander_light_margin:
		return false
	return _roam_max_radius <= 0.0 or from_tower <= _roam_max_radius


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
	# Grid-plane waypoints (x, y) are world (x, 0, y) — see BuildManager.
	var waypoint := Vector3(_path[_path_index].x, 0.0, _path[_path_index].y)
	if global_position.distance_to(waypoint) < 0.1875:
		_path_index += 1
		return
	velocity = global_position.direction_to(waypoint) * (type.move_speed / PX_PER_UNIT)
	# Daytime roamers and camp guards lurk in the dark and never set foot in the
	# light: if this step would cross into the safe zone, stop at its edge and drop the path
	# (a fresh one is picked next tick). ASSAULT monsters ignore this — the
	# night horde is meant to march through the village to the tower.
	if behavior != Behavior.ASSAULT and _safe_radius > 0.0:
		var next_pos := global_position + velocity * get_physics_process_delta_time()
		# Refuse the step only if it enters the light *or* pushes deeper in.
		# Outward steps are always allowed: a roamer that somehow ends up inside
		# (a collision slide, future knockback) must be able to walk itself out
		# instead of freezing on the spot — every direction would otherwise read
		# as "inside the safe zone" and pin it there for good.
		if _in_safe_zone(next_pos) and next_pos.distance_to(_tower.global_position) \
				<= global_position.distance_to(_tower.global_position):
			velocity = Vector3.ZERO
			_path_index = _path.size()
			_light_blocked = true
			return
	move_and_slide()


## Host only: night fell while this roamer was still alive — it turns on the
## tower and joins the assault instead of being burned off. Drops the wander
## state and repaths to the heart; the safe-zone block in _advance_path is keyed
## on ROAM, so it may now walk into the village like the rest of the horde.
func host_join_assault() -> void:
	if not multiplayer.is_server() or behavior == Behavior.ASSAULT:
		return
	behavior = Behavior.ASSAULT
	_wander_pause = 0.0
	_light_blocked = false
	_repath()


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
		# Killed, as opposed to despawned — announced before the free so a camp
		# can count its garrison down. Dawn's wipe and the run-end clear both go
		# through queue_free() alone and deliberately never reach here.
		died.emit()
		# Freeing on the host despawns it on every peer via the spawner.
		queue_free()


## Host only: bring a late joiner up to date.
func host_send_snapshot(peer_id: int) -> void:
	_sync_hp.rpc_id(peer_id, hp)


func _repath() -> void:
	if behavior == Behavior.GUARD:
		# A guard has no standing destination — its next path is chosen in
		# _guard (chase, or walk back to its post). Clearing is what makes the
		# grid_changed hookup below correct for it: an in-flight path through a
		# cell that just became solid is dropped, not followed into a wall.
		_path = PackedVector2Array()
		_path_index = 0
		return
	_path = _build_manager.path_to_heart(global_position)
	_path_index = 0


func _attack_range() -> float:
	return type.attack_range / PX_PER_UNIT


@rpc("authority", "call_local", "reliable")
func _sync_hp(new_hp: int) -> void:
	hp = new_hp


## Called by WorldLight every frame — unshaded billboards don't react to
## lights, so the day/night tint is handed to us and composed with the hp fade.
func set_light_tint(tint: Color) -> void:
	_light_tint = tint
	_update_appearance()


func _update_appearance() -> void:
	if _sprite == null:
		return
	var color := _light_tint
	color.a = lerpf(0.4, 1.0, float(hp) / float(maxi(type.max_hp, 1)))
	_sprite.modulate = color
