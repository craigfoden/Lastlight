class_name Player3D
extends CharacterBody3D
## One player character in the 3D world. The node is named after the owning
## peer's id, and that peer is the multiplayer authority: each player simulates
## its own movement locally and the MultiplayerSynchronizer replicates position
## to everyone else — the same deliberate exception to host authority as the 2D
## Player (see "Authority model" in docs/ARCHITECTURE.md).
##
## Phase-6 port: movement, camera rig, name tag, sync, harvesting, plus the 2D
## Player's combat (aim/cast/dodge) and host-authoritative survival
## (hp/downed/revive/respawn). Tint-by-light arrives with phase 7.

const ProjectileScene := preload("res://scenes/abilities3d/projectile_3d.tscn")
const SnareTrapScene := preload("res://scenes/abilities3d/snare_trap_3d.tscn")

## 2D data resources carry over untouched; speeds there are px/s on 32 px
## cells, so 3D consumers convert to world units at the boundary.
const PX_PER_UNIT := 32.0

## Camera yaw: screen-up is world 45 degrees (the prototype's trick). Movement,
## stick aim, and dodge directions all rotate through this.
const CAMERA_YAW := 45.0

@export var class_type: ClassType

@export_group("Survival")
## A downed teammate is revived when a living one stands this close... (2D: 64 px)
@export var revive_range := 2.0
## ...for this long.
@export var revive_time := 2.0
## No teammate in reach? The village calls you back after this long.
@export var respawn_time := 8.0
## Fraction of max hp restored on revive vs a full village respawn.
@export var revive_hp_fraction := 0.5
## Where a village respawn drops you (relative to the tower at the origin;
## 2D: (0, 120) px).
@export var respawn_offset := Vector3(0, 0, 3.75)
## Host-side floor between damage instances, so a swarm can't instantly melt you.
@export var hurt_cooldown := 0.4

## Talent hook (applied from the local profile on spawn).
var move_speed_mult := 1.0

## Host-authoritative survival state, replicated to every peer (this node's
## authority is the owning CLIENT, so host broadcasts use "any_peer" + a
## sender-is-host guard, never "authority" — see GOTCHAS).
var max_hp := 1
var hp := 1:
	set(value):
		hp = value
		_update_survival_appearance()
var downed := false:
	set(value):
		downed = value
		_update_survival_appearance()

## Dev hook (--auto-walk): with no input held, the local player strolls in a
## circle so movement replication can be asserted from headless smoke runs.
var auto_walk := false
var _walk_phase := 0.0

var _hurt_cd := 0.0        # host-only: time until damage can land again
var _down_time := 0.0      # host-only: seconds spent downed
var _revive_progress := 0.0  # host-only: seconds a teammate has been reviving

var _cooldowns := {}  # ability id -> seconds remaining
var _dodge_cooldown := 0.0
var _dodge_time := 0.0
var _dodge_direction := Vector3.ZERO
var _aim := Vector3.RIGHT
var _deploy_seq := 0  # host-side counter for deterministic deployable names

@onready var sprite: Sprite3D = $Sprite3D
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var name_label: Label3D = $NameLabel
@onready var interact_range: Area3D = $InteractRange


func _enter_tree() -> void:
	# The host spawns us named "<peer id>". Authority must be set before
	# _ready so the synchronizer starts out owned by the right peer.
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	sprite.texture = class_type.sprite
	var is_local := is_multiplayer_authority()
	if is_local:
		# Talents come from MY profile and only affect the character I
		# simulate — meta-progression needs no networking at all.
		move_speed_mult = Profile.modifiers_for(class_type.id).get(&"move_speed_mult", 1.0)
	camera.current = is_local
	max_hp = class_type.max_hp
	hp = max_hp
	# Remote players are moved by the synchronizer, not by physics.
	set_physics_process(is_local)
	# The host runs survival logic (damage/revive/respawn) for EVERY player,
	# including the ones it doesn't simulate movement for.
	set_process(multiplayer.is_server())
	Network.player_list_changed.connect(_refresh_name)
	_refresh_name()
	print("[Player] Spawned peer %d (local: %s) at %s"
			% [get_multiplayer_authority(), is_local, position])


func _physics_process(delta: float) -> void:
	for ability_id in _cooldowns:
		_cooldowns[ability_id] = maxf(_cooldowns[ability_id] - delta, 0.0)
	_dodge_cooldown = maxf(_dodge_cooldown - delta, 0.0)
	_update_aim()
	if downed:
		# Downed: no walking, no rolling — wait for a revive or the village call.
		velocity = Vector3.ZERO
		move_and_slide()
		return
	if _dodge_time > 0.0:
		# Mid-roll: locked direction, burst speed, no steering.
		_dodge_time -= delta
		velocity = _dodge_direction * (class_type.dodge_speed / PX_PER_UNIT)
		move_and_slide()
		return
	# Camera-relative WASD on the ground plane. No gravity — the game is
	# top-down and the body floats pinned to y = 0 (motion_mode is FLOATING).
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := _camera_relative(Vector3(input.x, 0.0, input.y))
	if auto_walk and direction == Vector3.ZERO:
		_walk_phase += delta
		direction = Vector3(cos(_walk_phase * 0.8), 0.0, sin(_walk_phase * 0.8))
	velocity = direction * (class_type.move_speed / PX_PER_UNIT) * move_speed_mult
	move_and_slide()


func _camera_relative(direction: Vector3) -> Vector3:
	return Basis(Vector3.UP, deg_to_rad(CAMERA_YAW)) * direction


func _update_aim() -> void:
	# Right stick wins when it is deflected; otherwise aim at the mouse's
	# point on the ground plane — the 3D twin of the 2D mouse aim.
	var stick := Vector3(
			Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
			0.0,
			Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > 0.3:
		_aim = _camera_relative(stick.normalized())
		return
	var mouse := get_viewport().get_mouse_position()
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(
			camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if hit == null:
		return
	var to_mouse: Vector3 = hit - global_position
	to_mouse.y = 0.0
	if to_mouse.length() > 0.125:
		_aim = to_mouse.normalized()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or downed:
		return
	if event.is_action_pressed("interact"):
		try_harvest()
	elif event.is_action_pressed("attack"):
		try_cast_toward(class_type.basic_attack, _aim)
	elif event.is_action_pressed("ability_1"):
		try_cast_toward(class_type.ability_1, _aim)
	elif event.is_action_pressed("ability_2"):
		try_cast_toward(class_type.ability_2, _aim)
	elif event.is_action_pressed("dodge"):
		_try_dodge()


func cooldown_remaining(ability: AbilityType) -> float:
	return _cooldowns.get(ability.id, 0.0)


func dodge_cooldown_remaining() -> float:
	return _dodge_cooldown


## Local authority only. Cooldown is enforced here (client side); the host
## only checks ownership — an accepted friends-co-op trade-off (see docs).
func try_cast_toward(ability: AbilityType, direction: Vector3) -> void:
	if ability == null or cooldown_remaining(ability) > 0.0:
		return
	_aim = direction.normalized() if direction != Vector3.ZERO else _aim
	_cooldowns[ability.id] = ability.cooldown
	request_cast.rpc_id(1, ability.id, _aim)


func _try_dodge() -> void:
	if _dodge_cooldown > 0.0 or _dodge_time > 0.0:
		return
	_dodge_cooldown = class_type.dodge_cooldown
	_dodge_time = class_type.dodge_duration
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_dodge_direction = _camera_relative(Vector3(input.x, 0.0, input.y)).normalized() \
			if input != Vector2.ZERO else _aim


@rpc("any_peer", "call_local", "reliable")
func request_cast(ability_id: StringName, aim: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender != get_multiplayer_authority():
		return  # only the owner may cast for this character
	var ability := _ability_by_id(ability_id)
	if ability == null:
		return
	aim = aim.normalized() if aim != Vector3.ZERO else Vector3.RIGHT
	match ability.kind:
		AbilityType.Kind.PROJECTILE:
			_spawn_projectile.rpc(global_position, aim, ability_id)
		AbilityType.Kind.DEPLOYABLE:
			_deploy_seq += 1
			_spawn_deployable.rpc(global_position, ability_id, _deploy_seq)


# Every peer spawns an identical local copy; only the host's deals damage.
# NOTE "any_peer" + sender guard, NOT "authority": this node's authority is
# the owning CLIENT, so a host broadcast would be rejected (see GOTCHAS).
@rpc("any_peer", "call_local", "reliable")
func _spawn_projectile(from: Vector3, direction: Vector3, ability_id: StringName) -> void:
	if not _sender_is_host():
		return
	var shot: Projectile3D = ProjectileScene.instantiate()
	shot.setup(_ability_by_id(ability_id), from, direction)
	get_parent().add_child(shot)


@rpc("any_peer", "call_local", "reliable")
func _spawn_deployable(at: Vector3, ability_id: StringName, seq: int) -> void:
	if not _sender_is_host():
		return
	var trap: SnareTrap3D = SnareTrapScene.instantiate()
	# Deterministic name so the host's consume RPC resolves on every peer.
	trap.name = "Trap_%s_%d" % [name, seq]
	trap.setup(_ability_by_id(ability_id), at)
	get_parent().add_child(trap)


func _sender_is_host() -> bool:
	# 0 = not inside a remote RPC (a local call on the host itself).
	return multiplayer.get_remote_sender_id() in [0, 1]


# --- Survival (host-authoritative) -----------------------------------------

# Host only: ticks the hurt cooldown for everyone and drives downed players
# toward revive or respawn. Runs on the host for every player node (movement
# still simulates only on the owning peer).
func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_hurt_cd = maxf(_hurt_cd - delta, 0.0)
	if not downed:
		return
	_down_time += delta
	if _living_teammate_near() != null:
		_revive_progress += delta
		if _revive_progress >= revive_time:
			_host_recover(revive_hp_fraction, false)
			print("[Player] %s revived by a teammate" % name)
	else:
		_revive_progress = 0.0
		if _down_time >= respawn_time:
			_host_recover(1.0, true)
			print("[Player] %s respawned at the village" % name)


## Host only: enemies (and anything hostile) whittle players down through here.
func host_take_damage(amount: int) -> void:
	if not multiplayer.is_server() or downed or hp <= 0 or _hurt_cd > 0.0:
		return
	_hurt_cd = hurt_cooldown
	var new_hp := maxi(hp - amount, 0)
	_sync_hp.rpc(new_hp)
	if new_hp == 0:
		_down_time = 0.0
		_revive_progress = 0.0
		_sync_downed.rpc(true)
		print("[Player] %s was downed" % name)


## Host only: bring a late joiner up to date on this player's condition.
func host_send_snapshot(peer_id: int) -> void:
	_sync_hp.rpc_id(peer_id, hp)
	_sync_downed.rpc_id(peer_id, downed)


# Host only: back on your feet with a share of max hp; a village respawn also
# teleports you home (the owning peer moves itself — it holds position authority).
func _host_recover(hp_fraction: float, to_village: bool) -> void:
	_down_time = 0.0
	_revive_progress = 0.0
	_sync_downed.rpc(false)
	_sync_hp.rpc(maxi(int(round(max_hp * hp_fraction)), 1))
	if to_village:
		var jitter := Vector3(0, 0, 0.375).rotated(Vector3.UP, randf() * TAU)
		_respawn_at.rpc_id(get_multiplayer_authority(), respawn_offset + jitter)


func _living_teammate_near() -> Player3D:
	for node in get_tree().get_nodes_in_group("players"):
		var mate := node as Player3D
		if mate == null or mate == self or mate.downed or mate.hp <= 0:
			continue
		if global_position.distance_to(mate.global_position) <= revive_range:
			return mate
	return null


# Broadcast by the host; only the owning peer (position authority) may move.
@rpc("any_peer", "call_local", "reliable")
func _respawn_at(point: Vector3) -> void:
	if not _sender_is_host() or not is_multiplayer_authority():
		return
	global_position = point
	_dodge_time = 0.0
	velocity = Vector3.ZERO


@rpc("any_peer", "call_local", "reliable")
func _sync_hp(new_hp: int) -> void:
	if not _sender_is_host():
		return
	hp = new_hp


@rpc("any_peer", "call_local", "reliable")
func _sync_downed(is_downed: bool) -> void:
	if not _sender_is_host():
		return
	downed = is_downed


func _update_survival_appearance() -> void:
	if sprite == null:
		return
	if downed:
		# Greyed-out while you wait for help (the 2D slump rotation reads
		# wrong on a Y-billboard, so the tint carries the state alone).
		sprite.modulate = Color(0.5, 0.5, 0.6, 0.7)
	else:
		var fraction := float(hp) / float(maxi(max_hp, 1))
		sprite.modulate = Color(1, 1, 1).lerp(Color(1, 0.5, 0.5), 1.0 - fraction)


func _ability_by_id(ability_id: StringName) -> AbilityType:
	for ability in [class_type.basic_attack, class_type.ability_1, class_type.ability_2]:
		if ability != null and ability.id == ability_id:
			return ability
	return null


func try_harvest() -> void:
	var target := _nearest_harvestable()
	if target != null:
		# Ask the host: it validates range/amount and updates the pool.
		target.request_harvest.rpc_id(1)


func _nearest_harvestable() -> ResourceNode3D:
	var best: ResourceNode3D = null
	var best_dist := INF
	for body in interact_range.get_overlapping_bodies():
		var node := body as ResourceNode3D
		if node == null or node.amount <= 0:
			continue
		var dist := global_position.distance_squared_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best = node
	return best


func _refresh_name() -> void:
	var info: Dictionary = Network.players.get(get_multiplayer_authority(), {})
	name_label.text = info.get("name", "...")
