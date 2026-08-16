class_name ResourceNode
extends StaticBody3D
## A harvestable world object (tree, rock, essence wisp) in the 3D world.
## Host-authoritative, same RPC lane as the 2D ResourceNode: players *request*
## a harvest; the host validates it and broadcasts the result. The node never
## touches the material pool itself — it announces the harvest with a signal
## and the game scene routes it (signals up, calls down).
##
## Variants (LootCache) extend this rather than duplicating the lane: the RPCs
## below stay the only harvest path in the game, and a subclass changes what it
## *refuses* (`harvest_block_reason`), what it *pays* (`_emit_payout`), and what
## the prompt *says* (`interact_prompt`) — never how the request travels.

## Fired on the host when the node is felled, carrying the WHOLE payout —
## chopping is progress, not income (see `depleted_yield`).
signal harvested(material_type: MaterialType, count: int)

## Fired on every peer when stock hits zero (amount is replicated), so
## derived state — like the build grid freeing this cell — stays in lockstep.
signal depleted

## The other half of `depleted`: fired on every peer when a node that had run
## dry comes back (see `host_regrow`). The build grid takes its cell back on
## this, which is the whole reason it is a signal and not just a number change.
signal regrown

## How close the harvesting player must be, in world units (1 unit = 1 cell;
## this is the 2D game's 64 px). Checked on the host — never trust the
## client's own overlap test.
const HARVEST_RANGE := 2.0

@export var material_type: MaterialType
## How many chops the node takes to fell. Stock is *work remaining*, not stock
## of material — nothing is paid out until it reaches zero.
@export var starting_amount := 5
## Chops removed per harvest request.
@export var yield_per_harvest := 1
## What felling the node pays, awarded in one lump on the final chop. Flat
## regardless of how many chops it took, so a fat near-village tree is quicker
## income per chop than a scrawny far one.
@export var depleted_yield := 4
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
		elif previous <= 0 and amount > 0 and _grown_once:
			# Guarded on having grown before, so the initial `amount =
			# starting_amount` in _ready is a birth rather than a regrowth — a
			# node that announced itself regrown on the frame it was created
			# would have the build grid block a cell it never freed.
			regrown.emit()

var _visual: Node3D
var _sprite: Sprite3D
## False until this node has been stocked for the first time — see the `amount`
## setter.
var _grown_once := false

@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	# Group membership ("resource_nodes") is declared in the scene file.
	if visual_scene != null:
		_visual = visual_scene.instantiate() as Node3D
		add_child(_visual)
		# A billboard look (the essence wisp) doesn't react to real lights, so
		# it joins the hand-tinted set WorldLight drives each frame — otherwise
		# it would glow full-bright out in the dark wilds.
		_sprite = _visual.get_node_or_null("Sprite3D") as Sprite3D
		if _sprite != null:
			add_to_group("billboards")
	amount = starting_amount
	_grown_once = true


## Host only: fell this node without anyone chopping it. Exists for the
## `--strip-nodes` smoke hook, and deliberately shares the ordinary path — the
## same broadcast and the same payout — so what it produces is indistinguishable
## from a player's last chop.
func host_fell() -> void:
	if not multiplayer.is_server() or amount <= 0:
		return
	_sync_amount.rpc(0)
	harvested.emit(material_type, depleted_yield)


## Host only: this node comes back. Travels down the same `_sync_amount` lane a
## chop does, so a client learns about regrowth exactly the way it learns about
## everything else that happens to a resource node — there is no second path.
##
## The caller (Regrowth) is responsible for checking that the cell is still
## FREE: a node that regrows under a wall, under a player, or across the last
## remaining route to the tower would be a worse bug than a bare map.
func host_regrow(stock: int) -> void:
	if not multiplayer.is_server() or amount > 0 or stock <= 0:
		return
	_sync_amount.rpc(stock)
	print("[ResourceNode] %s regrew (%s, %d to fell)" % [name, material_type.id, stock])


## Called by WorldLight every frame (billboard visuals only — meshes are lit
## by the real lights).
func set_light_tint(tint: Color) -> void:
	if _sprite != null:
		_sprite.modulate = tint


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
	# Variant gate (a loot cache still under guard). Checked here so the refusal
	# is host-authoritative like every other harvest rule — the client's prompt
	# only *predicts* it.
	var refusal := harvest_block_reason()
	if refusal != "":
		print("[ResourceNode] %s refused %s: %s" % [player.name, name, refusal])
		return
	var chopped: int = mini(yield_per_harvest, amount)
	var remaining := amount - chopped
	_sync_amount.rpc(remaining)
	if remaining > 0:
		print("[ResourceNode] %s chopped %s (%d to go)"
				% [player.name, material_type.id, remaining])
		return
	# Felled: the whole node pays out at once.
	_emit_payout(player)


## "" when a harvest may proceed, otherwise the host's reason for refusing it.
## Overridden by variants; the base node has no gate beyond range and stock.
func harvest_block_reason() -> String:
	return ""


## What this node pays when its last chop lands, host-side. `harvested` may be
## emitted more than once (a loot cache pays several materials), which the game
## scene's router already handles one material at a time.
func _emit_payout(player: Node3D) -> void:
	harvested.emit(material_type, depleted_yield)
	print("[ResourceNode] %s felled a %s node for %d"
			% [player.name, material_type.id, depleted_yield])


## The interact prompt the HUD shows while this node is the nearest harvestable
## — including *why* it would be refused, so the prompt can never promise a
## harvest `request_harvest` would turn down. Lives on the node (not in a HUD
## type-check) so a variant's gate and its prompt are written together.
func interact_prompt() -> String:
	return "E  Chop %s  (%d left → %d)" % [
			material_type.display_name, amount, depleted_yield]


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
