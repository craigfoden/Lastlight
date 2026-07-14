class_name ResourceNode
extends StaticBody3D
## A harvestable world object (tree, rock, essence wisp) in the 3D world.
## Host-authoritative, same RPC lane as the 2D ResourceNode: players *request*
## a harvest; the host validates it and broadcasts the result. The node never
## touches the material pool itself — it announces the harvest with a signal
## and the game scene routes it (signals up, calls down).

signal harvested(material_type: MaterialType, count: int)

## Fired on every peer when stock hits zero (amount is replicated), so
## derived state — like the build grid freeing this cell — stays in lockstep.
signal depleted

## How close the harvesting player must be, in world units (1 unit = 1 cell;
## this is the 2D game's 64 px). Checked on the host — never trust the
## client's own overlap test.
const HARVEST_RANGE := 2.0

@export var material_type: MaterialType
@export var starting_amount := 5
@export var yield_per_harvest := 1
## The node's look, instantiated in _ready — WorldGen picks it to match the
## material (tree mesh, rock mesh, wisp billboard) before add_child.
@export var visual_scene: PackedScene

var amount := 0:
	set(value):
		var previous := amount
		amount = value
		_update_appearance()
		if previous > 0 and amount <= 0:
			depleted.emit()

var _visual: Node3D

@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	# Group membership ("resource_nodes") is declared in the scene file.
	if visual_scene != null:
		_visual = visual_scene.instantiate() as Node3D
		add_child(_visual)
	amount = starting_amount


## Called by players via rpc_id(1, ...); executes on the host.
@rpc("any_peer", "call_local", "reliable")
func request_harvest() -> void:
	if not multiplayer.is_server():
		return
	if amount <= 0:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var player := _find_player(sender)
	if player == null:
		return
	if player.global_position.distance_to(global_position) > HARVEST_RANGE:
		return
	var taken: int = mini(yield_per_harvest, amount)
	_sync_amount.rpc(amount - taken)
	harvested.emit(material_type, taken)
	print("[ResourceNode] %s harvested %d %s (%d left)"
			% [player.name, taken, material_type.id, amount])


## Host only: bring a late joiner up to date.
func host_send_snapshot(peer_id: int) -> void:
	_sync_amount.rpc_id(peer_id, amount)


@rpc("authority", "call_local", "reliable")
func _sync_amount(remaining: int) -> void:
	amount = remaining


## The 3D player (phase 3) keeps the 2D contract: group "players", node named
## after its peer id.
func _find_player(peer_id: int) -> Node3D:
	for node in get_tree().get_nodes_in_group("players"):
		if node is Node3D and node.name == str(peer_id):
			return node
	return null


func _update_appearance() -> void:
	if _collision == null:
		return
	if amount <= 0:
		# Depleted: vanish and stop blocking movement.
		visible = false
		_collision.set_deferred("disabled", true)
		return
	visible = true
	_collision.set_deferred("disabled", false)
	# Shrink a little as it runs out so players can read remaining stock (the
	# 2D game fades sprite alpha; meshes read better scaled).
	if _visual != null:
		var fraction := float(amount) / float(maxi(starting_amount, 1))
		_visual.scale = Vector3.ONE * lerpf(0.55, 1.0, fraction)
