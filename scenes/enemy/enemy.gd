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
##
## All three behaviours share one more thing since session 18: they will break a
## building rather than take an absurd way round it (`breach_ratio`). See
## `_handle_breach` for why that is a ratio and not a flag.

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

## How much longer the way round has to be than the way through before this
## monster stops respecting the maze and starts breaking it (session 18).
##
## The never-block-the-path rule means a legal maze always leaves *a* route, so
## before this a wall was an absolute: a player could funnel the entire night
## through one corridor forever, and a camp's doorway could be sealed with two
## walls while the garrison stood and watched. Making walls simply breakable
## would have thrown the tower defence out with it. This is the middle: a
## short detour is what walls are FOR and is walked without complaint; a detour
## this many times the straight line is a wall being used as a cheat, and the
## horde takes it down instead. The dial is the ratio, not the wall's hp.
@export var breach_ratio := 2.5
## Recomputed at most this often, in seconds — walking the path length is cheap
## but not free, and the answer only changes when the grid does.
@export var breach_recheck := 0.5

## Seconds a corpse stays in the world, fading out and sinking, before the host
## frees it. Monsters used to vanish on the frame they died, which reads as a
## bug rather than as a kill.
##
## The host holds the free for this long instead of every peer animating a node
## that is already gone, because the alternative is a despawn packet arriving
## mid-fade and cutting it short on exactly the peers with the worst latency.
## Everything that counts monsters already tests `hp > 0` — the wave cap, the
## HUD's foe count, tower targeting, a camp's tally — so a corpse is inert.
@export var death_fade := 0.5

@export_group("Crowding")
## How close two monsters get before they start shouldering each other apart,
## in cells. The body capsule is 0.5 cells across, so anything below that is no
## separation at all; much above it and a horde walks up a corridor in single
## file, which looks stranger than the overlap it was meant to fix.
@export var separation_radius := 0.85
## How much of this monster's speed is spent pushing clear of its neighbours.
## Deliberately well under 1: separation is a lean, not a stampede, and at full
## strength a crowd walking into a wall shoves its own front rank through it.
@export var separation_strength := 0.55
## Seconds between separation recalculations. Every monster asking every other
## monster where it is, every physics tick, is the one part of this that scales
## badly (39 camp guards stand in the world from the first frame — see the
## roadmap), so the answer is computed a few times a second and reused. At
## walking pace nothing moves far enough between samples to see the difference.
@export var separation_interval := 0.1

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
## The structure this monster has decided to break rather than walk around, and
## the countdown to re-asking whether it still should.
var _breach_target: Building = null
var _breach_cd := 0.0
## Cached push away from crowding neighbours, and the countdown to recomputing
## it (see `separation_interval`).
var _separation := Vector3.ZERO
var _separation_cd := 0.0
## GUARD only: the spot this one guard stands on, the middle of the site it
## holds, and how far from that middle it will stray. `_post` is where it walks
## back to; `_home` is what the leash measures against (see `_guard`).
var _post := Vector3.ZERO
var _home := Vector3.ZERO
var _leash := 0.0
## GUARD only: walking back to its post, and refusing to chase until it arrives.
var _returning := false
var _light_tint := Color.WHITE  # day/night tint, driven by WorldLight
## Seconds left of this monster's death fade; zero while it is alive. Runs on
## every peer, driven by the observed hp reaching zero.
var _dying := 0.0

@onready var _sprite: Sprite3D = $Sprite3D
@onready var _animator: SpriteAnimator = $SpriteAnimator


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
	# A guard is spawned standing on its post, so that is where it belongs.
	_post = start_position
	_build_manager = build_manager
	_tower = tower
	behavior = new_behavior
	_safe_radius = safe_radius
	_roam_max_radius = roam_max_radius
	_home = home
	_leash = leash


func _ready() -> void:
	_sprite.texture = type.texture
	_animator.setup(_sprite, self, $Shadow)
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
	# Ticked once here rather than inside each behaviour: a root is a duration in
	# wall-clock seconds, and the three copies of this that used to sit in the
	# movement branches quietly paused it whenever the monster was busy swinging.
	_root_remaining = maxf(_root_remaining - delta, 0.0)
	_breach_cd = maxf(_breach_cd - delta, 0.0)
	_update_separation(delta)
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
		_hold_position()
		_swing_at(delta, _tower)
		return
	if _handle_breach(delta, _tower.global_position):
		return
	if _root_remaining > 0.0:
		# Rooted: no walking (attacking, above, still works).
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
		_hold_position()
		_swing_at(delta, target)
		return
	if target != null and _handle_breach(delta, target.global_position):
		return
	if _root_remaining > 0.0:
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
#
# `_post` (where this one guard stands) and `_home` (the middle of the camp) are
# two different places and used to be the same one. A guard measured "am I home"
# against the camp centre, so every garrison walked into the middle of its own
# courtyard on the first tick and stood there as a single stack of sprites —
# found by the crowding hook while adding separation steering (session 18). The
# leash still measures from the centre, because it is the *site* you cannot pull
# a garrison away from.
func _guard(delta: float) -> void:
	var target := _nearest_target()
	if target != null and global_position.distance_to(target.global_position) <= _attack_range():
		_hold_position()
		_swing_at(delta, target)
		return
	# A garrison that has been walled into its own camp breaks the wall down.
	# Whether the players sealed the doorway to shoot through the gap or simply
	# built across it, the answer is the same and it is not "stand there".
	if _handle_breach(delta, target.global_position if target != null else _post):
		return
	if _root_remaining > 0.0:
		velocity = Vector3.ZERO
		return
	var home_dist := global_position.distance_to(_home)
	var post_dist := global_position.distance_to(_post)
	if _leash > 0.0 and home_dist >= _leash:
		_returning = true
	if _returning and post_dist <= guard_post_tolerance:
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
	if post_dist > guard_post_tolerance:
		if _path_index >= _path.size():
			_path = _build_manager.path_to(global_position, _post)
			_path_index = 0
		_advance_path()
		return
	# At its post with nothing to fight: stand — but still shoulder clear of a
	# neighbour who has ended up on the same spot.
	_hold_position()


# --- crowding ----------------------------------------------------------------

# Host only (nothing else physics-processes). Sums a push away from every
# neighbour standing too close, so a horde arriving at one cell spreads into the
# space around it instead of stacking into a single sprite with several health
# bars' worth of hp.
#
# This is steering, not collision. Enemies deliberately do not collide with each
# other (collision_mask is world-only): bodies that block each other jam solid
# in a corridor and the whole wave stops behind the one at the front. A push
# they can walk through crowds and unclumps without ever deadlocking.
func _update_separation(delta: float) -> void:
	_separation_cd -= delta
	if _separation_cd > 0.0:
		return
	_separation_cd = separation_interval
	var push := Vector3.ZERO
	var radius_sq := separation_radius * separation_radius
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self:
			continue
		var other := node as Enemy
		if other == null or other.hp <= 0:
			continue
		var offset := global_position - other.global_position
		offset.y = 0.0
		var dist_sq := offset.length_squared()
		if dist_sq >= radius_sq or dist_sq < 0.0001:
			continue
		# Linear falloff: a neighbour at arm's length barely registers, one
		# standing on top of us is shoved off hard.
		var dist := sqrt(dist_sq)
		push += (offset / dist) * (1.0 - dist / separation_radius)
	_separation = push.limit_length(1.0)


# The sideways lean applied to whatever this monster is walking toward, in world
# units per second.
func _separation_velocity() -> Vector3:
	return _separation * (type.move_speed / PX_PER_UNIT) * separation_strength


# Standing to fight: no walking, but still shouldering clear of the neighbours,
# because a crowd around one target is exactly where the stacking used to be
# most obvious. Nothing shuffles out of its own reach doing this —
# `separation_radius` is well under every attack range in the game.
func _hold_position() -> void:
	velocity = _separation_velocity()
	if velocity == Vector3.ZERO:
		return
	# The light is still absolute for anything that isn't marching on the tower:
	# being jostled is not an excuse to step into the safe zone.
	if behavior != Behavior.ASSAULT and _safe_radius > 0.0:
		var next_pos := global_position + velocity * get_physics_process_delta_time()
		if _in_safe_zone(next_pos) and next_pos.distance_to(_tower.global_position) \
				<= global_position.distance_to(_tower.global_position):
			velocity = Vector3.ZERO
			return
	move_and_slide()


# --- breaching ---------------------------------------------------------------

# Host only. Decides whether the way round is worth walking, and if it is not,
# closes on whatever is in the way and hits it. Returns true when it has taken
# the tick over — the caller must then do nothing else this frame.
#
# The check is deliberately re-asked on a timer rather than latched: players
# sell and rebuild constantly, and a monster that decided to chew a wall three
# seconds ago should notice when someone opens a gate.
func _handle_breach(delta: float, goal: Vector3) -> bool:
	if _breach_cd <= 0.0:
		_breach_cd = breach_recheck
		_breach_target = _blocking_building(goal)
	var target := _breach_target
	if target == null or not is_instance_valid(target) or target.hp <= 0:
		_breach_target = null
		return false
	if global_position.distance_to(target.global_position) <= _breach_reach():
		_hold_position()
		_swing_at(delta, target)
		return true
	if _root_remaining > 0.0:
		velocity = Vector3.ZERO
		return true
	# Straight at it: it is between us and where we want to be by construction,
	# so there is nothing to path around.
	velocity = global_position.direction_to(target.global_position) \
			* (type.move_speed / PX_PER_UNIT) + _separation_velocity()
	move_and_slide()
	return true


# The structure worth breaking, or null when walking is still the better idea.
# "Better" is `breach_ratio`: a path that is a modest detour is what walls are
# for and is walked; one that is several times the straight line means the way
# through has been deliberately shut, and then whatever shut it is the target.
func _blocking_building(goal: Vector3) -> Building:
	if _build_manager == null:
		return null
	var straight := global_position.distance_to(goal)
	if straight < 1.0:
		return null
	if not _path.is_empty() and _remaining_path_length() <= straight * breach_ratio:
		return null
	return _build_manager.first_building_toward(global_position, goal)


# How much of the current path is still ahead of us, in cells. Measured from
# where the body actually is, not from the path's start — an enemy halfway down
# a long corridor is not still facing the whole of it.
func _remaining_path_length() -> float:
	var total := 0.0
	var previous := Vector2(global_position.x, global_position.z)
	for i in range(_path_index, _path.size()):
		total += previous.distance_to(_path[i])
		previous = _path[i]
	return total


# Reach against a structure. A building fills its whole cell while a monster is
# a point, so the half-cell is added back or a short-armed enemy stands against
# a wall it can never quite touch.
func _breach_reach() -> float:
	return _attack_range() + 0.5


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
	velocity = global_position.direction_to(waypoint) * (type.move_speed / PX_PER_UNIT) \
			+ _separation_velocity()
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
		# Freeing on the host despawns it on every peer via the spawner — held
		# back for the length of the fade every peer is now playing. The timer's
		# connection dies with the node, so an early despawn (dawn's wipe, the
		# run-end clear) cannot leave it firing into nothing.
		get_tree().create_timer(death_fade).timeout.connect(queue_free)


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
	# call_local, so this runs on every peer — the flash is seen by everyone
	# even though only the host decided the damage.
	if new_hp < hp:
		_animator.flash()
	if new_hp == 0 and hp > 0:
		# Same reason as the flash: the death is *observed* here, on every peer,
		# rather than announced from where the damage was dealt.
		_dying = death_fade
		_animator.upright = false
	hp = new_hp


# Runs on every peer (unlike _physics_process, which is host-only for an enemy)
# and does nothing at all until this monster is dead.
func _process(delta: float) -> void:
	if _dying <= 0.0:
		return
	_dying = maxf(_dying - delta, 0.0)
	_update_appearance()


## Called by WorldLight every frame — unshaded billboards don't react to
## lights, so the day/night tint is handed to us and composed with the hp fade.
func set_light_tint(tint: Color) -> void:
	_light_tint = tint
	_update_appearance()


func _update_appearance() -> void:
	if _sprite == null:
		return
	var color := _light_tint * _animator.tint_multiplier()
	color.a = lerpf(0.4, 1.0, float(hp) / float(maxi(type.max_hp, 1)))
	if hp <= 0:
		# Dead: fade the rest of the way out and sink into the ground, so the
		# body leaves rather than blinks out. The sink is handed to the animator
		# rather than applied here, because the animator owns `sprite.position`
		# outright — two writers and the bob would fight the fall (the same rule
		# that makes tinting go through `tint_multiplier`).
		var left := _dying / maxf(death_fade, 0.01)
		color.a *= left
		_animator.sink = 1.0 - left
	_sprite.modulate = color
