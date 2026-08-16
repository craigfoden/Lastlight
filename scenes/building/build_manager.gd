class_name BuildManager
extends Node3D
## Owns the 3D build grid: occupancy, the never-block-the-path rule, and the
## host-authoritative place/sell RPCs. The grid logic is the 2D BuildManager's,
## verbatim — AStarGrid2D never knew about rendering; only the world<->cell
## boundary changed (1 world unit = 1 cell, the grid plane is XZ).
##
## Buildings replicate through a MultiplayerSpawner; occupancy and the
## pathfinding grid are *derived* from the spawned nodes locally on every
## peer (via child enter/exit hooks), so they never need their own sync and
## clients can tint the placement ghost with the exact same rules the host
## enforces.

const BuildingScene := preload("res://scenes/building/building.tscn")

## The walkable grid changed (building placed/sold, scenery cleared) —
## anything following a path should recompute it.
signal grid_changed

## Everything placeable this run, in hotbar order. Includes every class's
## exclusives — see `types_for_class()` for the per-player view. Read straight
## off the `Buildings` registry rather than exported into game.tscn, so the
## roster is one list that the class-select screen can read too.
var buildable_types: Array[BuildingType] = Buildings.ALL

## Grid half-extent in cells; the region spans [-half, half). Matches the 2D
## grid (200x200 cells) and comfortably contains WorldGen's 93.75-cell extent.
@export var grid_half_extent := 100

var _astar := AStarGrid2D.new()
## cell (Vector2i) -> Building node. Placed structures only.
var _occupied := {}
## Cells that must stay free forever: spawn openings and the tower's heart.
var _reserved := {}
## Cells blocked by scenery (tower footprint, live resource nodes).
var _scenery := {}

var _team_materials: TeamMaterials
## Monotonic placement counter, part of every building's node name. A tower
## replacing a wall would otherwise collide with the wall still sitting in the
## tree, and Godot's auto-rename would differ per peer — breaking the
## same-path-everywhere rule the buildings' RPCs rely on.
var _place_seq := 0
var _opening_cells: Array[Vector2i] = []
## Where enemies are headed: a walkable cell at the glowing tower's base.
var _heart_cell := Vector2i.ZERO

@onready var _spawner: MultiplayerSpawner = $BuildingSpawner
@onready var _buildings: Node3D = $Buildings


func _ready() -> void:
	_spawner.spawn_function = _build_building
	_buildings.child_entered_tree.connect(_on_building_added)
	_buildings.child_exiting_tree.connect(_on_building_removed)
	# The grid region is laid out here rather than in setup(), which now waits
	# on the world seed arriving from the host. A client that joins on day 2 has
	# the host's already-placed buildings replicated to it the moment the
	# transport connects — strictly before its world exists — and every one of
	# them marks its cell solid on the way in. With the region still empty that
	# is an out-of-bounds write per building; it depends on nothing but an
	# export, so it belongs before the wait.
	var extent := grid_half_extent
	_astar.region = Rect2i(-extent, -extent, extent * 2, extent * 2)
	# 1 unit = 1 cell; point paths return cell centers (x.5, y.5) which ARE
	# world XZ coordinates in the 3D scene.
	_astar.cell_size = Vector2.ONE
	_astar.offset = Vector2(0.5, 0.5)
	# Orthogonal movement only: corridors and mazes behave predictably.
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()


## Injected by the Game scene once the world exists.
func setup(
		team_materials: TeamMaterials,
		opening_cells: Array[Vector2i],
		heart_cell: Vector2i,
		scenery_cells: Array[Vector2i]) -> void:
	_team_materials = team_materials
	_opening_cells = opening_cells
	_heart_cell = heart_cell

	for cell in scenery_cells:
		_scenery[cell] = true
		_astar.set_point_solid(cell)
	for cell in opening_cells:
		_reserved[cell] = true
	_reserved[heart_cell] = true

	# Live resource nodes block building; their cells free up when depleted.
	# amount is replicated, so this stays identical on every peer.
	for node in get_tree().get_nodes_in_group("resource_nodes"):
		if node.amount == 0 and not node.visible:
			continue
		var cell: Vector2i = world_to_cell(node.global_position)
		_scenery[cell] = true
		_astar.set_point_solid(cell)
		node.depleted.connect(_on_scenery_cleared.bind(cell))


func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(Vector2(pos.x, pos.z).floor())


## Center of a cell on the ground plane.
func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)


func type_by_id(type_id: StringName) -> BuildingType:
	for type in buildable_types:
		if type.id == type_id:
			return type
	return null


func building_at(cell: Vector2i) -> Building:
	return _occupied.get(cell)


## Grid-plane waypoints (x = world x, y = world z) from a position to the
## tower's heart cell. Consumers lift them onto the ground as (x, 0, y). The
## never-block rule guarantees a path exists from any open cell; partial
## paths cover the moment something is placed mid-walk (repath follows).
func path_to_heart(from: Vector3) -> PackedVector2Array:
	return _astar.get_point_path(_walkable_cell(world_to_cell(from)), _heart_cell, true)


## Grid-plane path between two arbitrary points — roaming monsters chasing a
## player. Both endpoints are nudged onto the nearest walkable cell first.
func path_to(from: Vector3, to: Vector3) -> PackedVector2Array:
	return _astar.get_point_path(
			_walkable_cell(world_to_cell(from)),
			_walkable_cell(world_to_cell(to)), true)


func _walkable_cell(cell: Vector2i) -> Vector2i:
	if not _astar.region.has_point(cell):
		cell = cell.clamp(_astar.region.position, _astar.region.end - Vector2i.ONE)
	if _astar.is_point_solid(cell):
		cell = _nearest_open_neighbor(cell)
	return cell


func _nearest_open_neighbor(cell: Vector2i) -> Vector2i:
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var neighbor: Vector2i = cell + offset
		if _astar.region.has_point(neighbor) and not _astar.is_point_solid(neighbor):
			return neighbor
	return cell


## The subset of `buildable_types` a given class may place: everything shared,
## plus that class's own exclusives. The hotbar, its number keys, and the ghost
## all index into THIS list, so slot numbers stay contiguous per class and the
## keys can never point at a different building than the buttons show.
func types_for_class(class_id: StringName) -> Array[BuildingType]:
	var result: Array[BuildingType] = []
	for type in buildable_types:
		if not type.placeable:
			continue
		if type.class_id == &"" or type.class_id == class_id:
			result.append(type)
	return result


## "" when placement is legal, otherwise a human-readable reason. Runs
## identically on clients (ghost tint) and on the host (the actual gate).
func placement_error(
		type: BuildingType,
		cell: Vector2i,
		builder_class: StringName = &"") -> String:
	if type == null:
		return "Unknown building type"
	if type.class_id != &"" and type.class_id != builder_class:
		return "Class exclusive (%s only)" % type.class_id
	# Upgrade tiers are reached by upgrading, never by naming them directly.
	# They have to sit in `buildable_types` for `type_by_id` to resolve them out
	# of a spawn packet, which would otherwise let a crafted `request_place` buy
	# a top tier outright and skip the line beneath it.
	if not type.placeable:
		return "%s is built by upgrading, not from scratch" % type.display_name
	if not _astar.region.has_point(cell):
		return "Out of bounds"
	var placed := resolve_placement(type, cell)
	var existing := building_at(cell)
	# Resolving to the building already standing means the click walked its
	# upgrade line and found no tier above. `placed != type` keeps that distinct
	# from an ordinary same-type collision (a wall on a wall), which is occupancy.
	if existing != null and placed == existing.type and placed != type:
		return "%s is fully upgraded" % placed.display_name
	var replaced := replaceable_at(cell, placed)
	if _scenery.has(cell) or (_occupied.has(cell) and replaced == null):
		return "Cell is occupied"
	if _reserved.has(cell):
		return "Cell must stay open"
	if _player_on(cell):
		return "Someone is standing here"
	if not _team_materials.can_afford(net_cost(type, cell)):
		return "Not enough materials"
	# A replacement swaps one solid cell for another, so it cannot change
	# reachability — and _would_block_path assumes the cell starts non-solid.
	if replaced == null and _would_block_path(cell):
		return "Would block every path to the tower"
	return ""


## What clicking `cell` while holding `type`'s hammer actually builds. Normally
## that is `type` itself — but when the cell already holds a building from the
## same upgrade line, the click means "upgrade this one" and resolves to that
## building's next tier. Walking the chain (rather than matching `type` alone)
## is what lets one hotbar slot drive a whole line: the Sentry hammer upgrades a
## Sentry II into a III just as it did I into II.
##
## A building already at its final tier resolves to *itself*, which
## `placement_error` reports as "fully upgraded" rather than "occupied".
func resolve_placement(type: BuildingType, cell: Vector2i) -> BuildingType:
	if type == null:
		return null
	var existing := building_at(cell)
	if existing == null:
		return type
	for tier in type.upgrade_chain():
		if tier == existing.type:
			return existing.type.upgrades_to if existing.type.upgrades_to != null \
					else existing.type
	return type


## The building on `cell` that building `type` would replace, or null if this is
## an ordinary empty-cell placement. Two things are replaceable:
## **its own next tier** (an upgrade — pass the *resolved* type), and
## **a wall under anything that attacks** (towers upgrade walls in place,
## session 11). Nothing else — no wall over a tower, no unrelated tower over a
## tower.
func replaceable_at(cell: Vector2i, type: BuildingType) -> Building:
	if type == null:
		return null
	var existing := building_at(cell)
	if existing == null:
		return null
	if existing.type.upgrades_to == type:
		return existing
	if type.attacks and not existing.type.attacks:
		return existing
	return null


## What clicking `cell` with `type` selected actually costs the pool: the
## *resolved* building's cost less the refund for whatever it replaces, so
## neither upgrading a wall into a tower nor a tower into its next tier is ever
## worse than selling and placing fresh. Tier .tres files therefore author a
## **gross** cost and the player pays the difference — the same convention
## walls and towers have used since session 11. Clamped at zero per material — a replacement
## worth more than the upgrade banks no change (can't happen with current data,
## and crediting it would need the sell path, not the place path).
func net_cost(type: BuildingType, cell: Vector2i) -> Dictionary:
	var placed := resolve_placement(type, cell)
	if placed == null:
		return {}
	var net: Dictionary = placed.cost.duplicate()
	var replaced := replaceable_at(cell, placed)
	if replaced == null:
		return net
	var refunded := replaced.type.refund()
	for material_id in refunded:
		var remaining := maxi(int(net.get(material_id, 0)) - refunded[material_id], 0)
		# Drop the line rather than leave a zero: `cost_text` renders every entry,
		# and "0 Bright Essence" in the upgrade hint is a lie about the price.
		if remaining > 0:
			net[material_id] = remaining
		else:
			net.erase(material_id)
	return net


# A building must never drop on a body — it would collide with and trap them.
# Runs identically on every peer (player positions are replicated), so the
# client's ghost tint matches the host's gate.
func _player_on(cell: Vector2i) -> bool:
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if player == null:
			continue
		if world_to_cell(player.global_position) == cell:
			return true
	return false


func _would_block_path(cell: Vector2i) -> bool:
	# Hypothetically place it, test every opening, then revert. The cell is
	# known non-solid here (occupancy/scenery were checked first).
	_astar.set_point_solid(cell, true)
	var blocked := false
	for opening in _opening_cells:
		if _astar.get_id_path(opening, _heart_cell).is_empty():
			blocked = true
			break
	_astar.set_point_solid(cell, false)
	return blocked


@rpc("any_peer", "call_local", "reliable")
func request_place(type_id: StringName, cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var builder_class: StringName = Network.players.get(sender, {}).get("class_id", &"")
	var type := type_by_id(type_id)
	var error := placement_error(type, cell, builder_class)
	if error != "":
		print("[Build] Rejected %s at %s: %s" % [type_id, cell, error])
		return
	# The click may mean "upgrade the tower already here" — resolve before
	# spending or spawning, so the pool and the spawn data agree on the tier.
	var placed := resolve_placement(type, cell)
	var replaced := replaceable_at(cell, placed)
	# Logged as well as spent: what the pool was actually charged is the one
	# number a reader can't derive from the .tres files (it nets off the refund
	# for whatever stood here), so the smoke tests assert on it.
	var spent := net_cost(type, cell)
	_team_materials.host_spend(spent)
	_place_seq += 1
	if replaced != null:
		# Retire the old building first; the seq in the node name keeps the two
		# from colliding while both are briefly in the tree (queue_free is
		# deferred).
		var replaced_id: StringName = replaced.type.id
		var upgraded := replaced.type.upgrades_to == placed
		replaced.queue_free()
		_spawner.spawn({"type_id": placed.id, "cell": cell, "seq": _place_seq})
		if upgraded:
			print("[Build] Upgraded %s to %s at %s (cost %s)"
					% [replaced_id, placed.id, cell, spent])
		else:
			print("[Build] Placed %s at %s, replacing %s (cost %s)"
					% [placed.id, cell, replaced_id, spent])
		return
	_spawner.spawn({"type_id": placed.id, "cell": cell, "seq": _place_seq})
	print("[Build] Placed %s at %s (cost %s)" % [placed.id, cell, spent])


@rpc("any_peer", "call_local", "reliable")
func request_sell(cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var building := building_at(cell)
	if building == null:
		return
	# Removal refunds by the building's own `refund_fraction` (walls 100 %,
	# towers 50 %) — BuildingType.refund() owns the rule, shared with the
	# sell-mode hover hint.
	var refunded := building.type.refund()
	for material_id in refunded:
		_team_materials.host_add(material_id, refunded[material_id])
	building.queue_free()
	print("[Build] Removed %s at %s (%d%% refund: %s)"
			% [building.type.id, cell,
			int(roundf(building.type.refund_fraction * 100.0)), refunded])


# Spawn function: runs on every peer, builds the identical node.
func _build_building(data: Dictionary) -> Node:
	var building := BuildingScene.instantiate()
	building.name = "Building_%d_%d_%d" % [data.cell.x, data.cell.y, data.seq]
	building.setup(type_by_id(data.type_id), data.cell)
	building.position = cell_to_world(data.cell)
	return building


# Occupancy/pathfinding derive from the replicated container on every peer.
func _on_building_added(node: Node) -> void:
	_occupied[node.cell] = node
	_astar.set_point_solid(node.cell)
	grid_changed.emit()


func _on_building_removed(node: Node) -> void:
	# A replaced wall leaves the tree *after* its tower has already claimed the
	# cell (queue_free is deferred on the host, and the spawn/despawn packets can
	# arrive in either order on a client). Only the current occupant may release
	# the cell — otherwise the replacement's own entry is erased and the grid
	# calls a tower-occupied cell walkable.
	if _occupied.get(node.cell) != node:
		grid_changed.emit()
		return
	_occupied.erase(node.cell)
	_astar.set_point_solid(node.cell, false)
	grid_changed.emit()


func _on_scenery_cleared(cell: Vector2i) -> void:
	_scenery.erase(cell)
	_astar.set_point_solid(cell, false)
	grid_changed.emit()
