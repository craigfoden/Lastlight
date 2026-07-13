class_name BuildManager
extends Node2D
## Owns the build grid: occupancy, the never-block-the-path rule, and the
## host-authoritative place/sell RPCs.
##
## Node2D (not Node) so the Y-sort chain from Game reaches the Buildings
## container — a CanvasItem under a plain Node is "topmost" and would escape
## the world's depth sorting (see the 3/4-view entry in ARCHITECTURE.md).
##
## Buildings replicate through a MultiplayerSpawner; occupancy and the
## pathfinding grid are *derived* from the spawned nodes locally on every
## peer (via child enter/exit hooks), so they never need their own sync and
## clients can tint the placement ghost with the exact same rules the host
## enforces.

const CELL_SIZE := 32
const BuildingScene := preload("res://scenes/building/building.tscn")

## The walkable grid changed (building placed/sold, scenery cleared) —
## anything following a path should recompute it.
signal grid_changed

## Everything placeable this run, in hotbar order.
@export var buildable_types: Array[BuildingType] = []

## Grid half-extent in cells; the region spans [-half, half). At 32 px/cell a
## half-extent of 100 is a 200×200-cell, 6400×6400 px world.
@export var grid_half_extent := 100

var _astar := AStarGrid2D.new()
## cell (Vector2i) -> Building node. Placed structures only.
var _occupied := {}
## Cells that must stay free forever: spawn openings and the tower's heart.
var _reserved := {}
## Cells blocked by scenery (tower footprint, live resource nodes).
var _scenery := {}

var _team_materials: TeamMaterials
var _opening_cells: Array[Vector2i] = []
## Where enemies are headed: a walkable cell at the glowing tower's base.
var _heart_cell := Vector2i.ZERO

@onready var _spawner: MultiplayerSpawner = $BuildingSpawner
@onready var _buildings: Node2D = $Buildings


func _ready() -> void:
	_spawner.spawn_function = _build_building
	_buildings.child_entered_tree.connect(_on_building_added)
	_buildings.child_exiting_tree.connect(_on_building_removed)


## Injected by the Game scene once the world exists.
func setup(
		team_materials: TeamMaterials,
		opening_cells: Array[Vector2i],
		heart_cell: Vector2i,
		scenery_cells: Array[Vector2i]) -> void:
	_team_materials = team_materials
	_opening_cells = opening_cells
	_heart_cell = heart_cell

	var extent := grid_half_extent
	_astar.region = Rect2i(-extent, -extent, extent * 2, extent * 2)
	_astar.cell_size = Vector2(CELL_SIZE, CELL_SIZE)
	# Point paths should return cell centers, not top-left corners.
	_astar.offset = Vector2(CELL_SIZE, CELL_SIZE) / 2.0
	# Orthogonal movement only: corridors and mazes behave predictably.
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()

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


func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i((pos / CELL_SIZE).floor())


## Center of a cell in world space.
func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL_SIZE + Vector2(CELL_SIZE, CELL_SIZE) / 2.0


func type_by_id(type_id: StringName) -> BuildingType:
	for type in buildable_types:
		if type.id == type_id:
			return type
	return null


func building_at(cell: Vector2i) -> Building:
	return _occupied.get(cell)


## World-space waypoints from a position to the tower's heart cell. The
## never-block rule guarantees a path exists from any open cell; partial
## paths cover the moment something is placed mid-walk (repath follows).
func path_to_heart(from: Vector2) -> PackedVector2Array:
	return _astar.get_point_path(_walkable_cell(world_to_cell(from)), _heart_cell, true)


## World-space path between two arbitrary points — roaming monsters chasing a
## player. Both endpoints are nudged onto the nearest walkable cell first.
func path_to(from: Vector2, to: Vector2) -> PackedVector2Array:
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
	if not _astar.region.has_point(cell):
		return "Out of bounds"
	if _occupied.has(cell) or _scenery.has(cell):
		return "Cell is occupied"
	if _reserved.has(cell):
		return "Cell must stay open"
	if _player_on(cell):
		return "Someone is standing here"
	if not _team_materials.can_afford(type.cost):
		return "Not enough materials"
	if _would_block_path(cell):
		return "Would block every path to the tower"
	return ""


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
	_team_materials.host_spend(type.cost)
	_spawner.spawn({"type_id": type_id, "cell": cell})
	print("[Build] Placed %s at %s" % [type_id, cell])


@rpc("any_peer", "call_local", "reliable")
func request_sell(cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var building := building_at(cell)
	if building == null:
		return
	# Removal refunds each material by the building's own `refund_fraction`
	# (walls 100 %, towers 50 % — see BuildingType). Fractions floor: no free
	# rounding-up of an odd cost.
	var fraction: float = building.type.refund_fraction
	var refunded := {}
	for material_id in building.type.cost:
		var amount := int(floor(building.type.cost[material_id] * fraction))
		if amount > 0:
			_team_materials.host_add(material_id, amount)
			refunded[material_id] = amount
	building.queue_free()
	print("[Build] Removed %s at %s (%d%% refund: %s)"
			% [building.type.id, cell, int(roundf(fraction * 100.0)), refunded])


# Spawn function: runs on every peer, builds the identical node.
func _build_building(data: Dictionary) -> Node:
	var building := BuildingScene.instantiate()
	building.name = "Building_%d_%d" % [data.cell.x, data.cell.y]
	building.setup(type_by_id(data.type_id), data.cell)
	building.position = cell_to_world(data.cell)
	return building


# Occupancy/pathfinding derive from the replicated container on every peer.
func _on_building_added(node: Node) -> void:
	_occupied[node.cell] = node
	_astar.set_point_solid(node.cell)
	grid_changed.emit()


func _on_building_removed(node: Node) -> void:
	_occupied.erase(node.cell)
	_astar.set_point_solid(node.cell, false)
	grid_changed.emit()


func _on_scenery_cleared(cell: Vector2i) -> void:
	_scenery.erase(cell)
	_astar.set_point_solid(cell, false)
	grid_changed.emit()
