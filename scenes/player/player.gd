class_name Player
extends CharacterBody2D
## One player character. The node is named after the owning peer's id, and that
## peer is the multiplayer authority: each player simulates their own movement
## locally and the MultiplayerSynchronizer replicates position to everyone else.
## This is a deliberate exception to host authority, for responsive movement —
## see "Authority model" in docs/ARCHITECTURE.md.

@export var move_speed := 150.0

@onready var camera: Camera2D = $Camera2D
@onready var name_label: Label = $NameLabel
@onready var interact_range: Area2D = $InteractRange


func _enter_tree() -> void:
	# The host spawns us named "<peer id>". Authority must be set before
	# _ready so the synchronizer starts out owned by the right peer.
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	var is_local := is_multiplayer_authority()
	camera.enabled = is_local
	# Remote players are moved by the synchronizer, not by physics.
	set_physics_process(is_local)
	Network.player_list_changed.connect(_refresh_name)
	_refresh_name()
	print("[Player] Spawned peer %d (local: %s) at %s"
			% [get_multiplayer_authority(), is_local, position])


func _physics_process(_delta: float) -> void:
	velocity = Input.get_vector("move_left", "move_right", "move_up", "move_down") * move_speed
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


func _refresh_name() -> void:
	var info: Dictionary = Network.players.get(get_multiplayer_authority(), {})
	name_label.text = info.get("name", "...")


func _nearest_harvestable() -> ResourceNode:
	var best: ResourceNode = null
	var best_dist := INF
	for body in interact_range.get_overlapping_bodies():
		var node := body as ResourceNode
		if node == null or node.amount <= 0:
			continue
		var dist := global_position.distance_squared_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best = node
	return best
