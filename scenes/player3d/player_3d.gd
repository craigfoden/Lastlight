class_name Player3D
extends CharacterBody3D
## One player character in the 3D world. The node is named after the owning
## peer's id, and that peer is the multiplayer authority: each player simulates
## its own movement locally and the MultiplayerSynchronizer replicates position
## to everyone else — the same deliberate exception to host authority as the 2D
## Player (see "Authority model" in docs/ARCHITECTURE.md).
##
## Phase-3/4 slim port: movement, camera rig, name tag, sync, harvesting.
## Combat and survival arrive with phase 6, tint-by-light with phase 7.

## 2D data resources carry over untouched; speeds there are px/s on 32 px
## cells, so 3D consumers convert to world units at the boundary.
const PX_PER_UNIT := 32.0

@export var class_type: ClassType

## Talent hook (applied from the local profile on spawn).
var move_speed_mult := 1.0

## Dev hook (--auto-walk): with no input held, the local player strolls in a
## circle so movement replication can be asserted from headless smoke runs.
var auto_walk := false
var _walk_phase := 0.0

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
	# Remote players are moved by the synchronizer, not by physics.
	set_physics_process(is_local)
	Network.player_list_changed.connect(_refresh_name)
	_refresh_name()
	print("[Player] Spawned peer %d (local: %s) at %s"
			% [get_multiplayer_authority(), is_local, position])


func _physics_process(delta: float) -> void:
	# Camera-relative WASD on the ground plane: screen-up is world 45 degrees
	# (the prototype's yaw trick). No gravity — the game is top-down and the
	# body floats pinned to y = 0 (motion_mode is FLOATING in the scene).
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var yaw := Basis(Vector3.UP, deg_to_rad(45.0))
	var direction := yaw * Vector3(input.x, 0.0, input.y)
	if auto_walk and direction == Vector3.ZERO:
		_walk_phase += delta
		direction = Vector3(cos(_walk_phase * 0.8), 0.0, sin(_walk_phase * 0.8))
	velocity = direction * (class_type.move_speed / PX_PER_UNIT) * move_speed_mult
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("interact"):
		try_harvest()


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
