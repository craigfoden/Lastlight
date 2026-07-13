class_name WorldGen
extends Node2D
## Deterministic world populator. From a fixed seed it scatters harvestable
## resource nodes (common wood/stone near the village, rarer essence further
## out) and scenery (solid obstacles + flat decor) so the map stops feeling
## empty. The layout is DERIVED from the seed and runs identically on every
## peer — never synced, same principle as the build grid. Resource *stock*
## still syncs through ResourceNode's own RPC lane.
##
## Distances encode the design rule "near = safe & common, far = rare": the
## safe zone (no monsters, see WaveDirector) sits inside `safe_radius`, and the
## row of cells at y = 0 is left clear so a path from the spawn openings to the
## tower heart always exists before anyone builds a thing.

const ResourceNodeScene := preload("res://scenes/world/resource_node.tscn")
const SceneryPropScene := preload("res://scenes/world/scenery_prop.tscn")
const CELL_SIZE := 32

## Baked constant, not randomised per run: every peer must generate the same
## world. A per-run seed would have to be synced before generation — a later
## map-generation step (see ROADMAP), not this one.
@export var world_seed := 20260713

## A clear plaza right around the tower — nothing spawns inside it.
@export var plaza_radius := 150.0
## Monsters never enter within this radius (WorldGen reads it too, to keep
## solid obstacles out of the safe gathering ring). The visual "safe zone".
@export var safe_radius := 480.0
## Boundary between the common near band and the essence-bearing mid band.
@export var mid_radius := 2000.0
## Nothing spawns beyond this from the origin (kept inside the ground + grid).
@export var world_extent := 3000.0

@export_group("Resources")
@export var wood: MaterialType
@export var stone: MaterialType
@export var essence_faint: MaterialType
@export var essence_bright: MaterialType
@export var essence_radiant: MaterialType
@export var tree_texture: Texture2D
@export var rock_texture: Texture2D
@export var wisp_texture: Texture2D
## How many resource nodes to scatter. High on purpose — materials are common,
## and the world is now ~4× the area, so the count rose to keep density up.
@export var resource_count := 380
## Stock on the closest nodes vs the furthest (lerped by distance).
@export var near_amount := 14
@export var far_amount := 5

@export_group("Scenery")
@export var solid_textures: Array[Texture2D] = []
@export var decor_textures: Array[Texture2D] = []
@export var scenery_count := 460
## Share of scenery that is solid cover (the rest is flat decor).
@export var solid_share := 0.45

var _used := {}  # cell (Vector2i) -> true; resources + solid props (one per cell)


func _ready() -> void:
	# Runs on host and clients alike; identical seed -> identical world.
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	_scatter_resources(rng)
	_scatter_scenery(rng)
	print("[WorldGen] Populated: %d resources, %d scenery props (seed %d)"
			% [resource_count, scenery_count, world_seed])


func _scatter_resources(rng: RandomNumberGenerator) -> void:
	for i in resource_count:
		var pos := _ring_point(rng, plaza_radius, world_extent)
		var cell := _cell(pos)
		if _blocked(cell):
			continue
		_used[cell] = true
		var dist := pos.length()
		var material := _material_for(dist, rng)
		var node := ResourceNodeScene.instantiate() as ResourceNode
		node.name = "Res_%d" % i
		node.position = _snap(pos)
		node.material_type = material
		node.starting_amount = _amount_for(dist)
		add_child(node)
		node.get_node("Sprite2D").texture = _texture_for(material)


func _scatter_scenery(rng: RandomNumberGenerator) -> void:
	for i in scenery_count:
		var solid := rng.randf() < solid_share
		# Solids stay out of the safe ring; decor may dress it (grass etc.).
		var inner := safe_radius if solid else plaza_radius
		var pos := _ring_point(rng, inner, world_extent)
		var textures := solid_textures if solid else decor_textures
		if textures.is_empty():
			continue
		var texture: Texture2D = textures[rng.randi() % textures.size()]
		if solid:
			var cell := _cell(pos)
			if _blocked(cell):
				continue
			_used[cell] = true
		var prop := SceneryPropScene.instantiate() as SceneryProp
		prop.name = "Prop_%d" % i
		prop.position = _snap(pos)
		prop.texture = texture
		prop.solid = solid
		add_child(prop)


# Uniform-in-annulus sampling so props spread evenly instead of clumping
# toward the centre.
func _ring_point(rng: RandomNumberGenerator, r_min: float, r_max: float) -> Vector2:
	var radius := sqrt(rng.randf() * (r_max * r_max - r_min * r_min) + r_min * r_min)
	var angle := rng.randf() * TAU
	return Vector2(radius, 0).rotated(angle)


func _material_for(dist: float, rng: RandomNumberGenerator) -> MaterialType:
	var r := rng.randf()
	if dist < safe_radius:
		return wood if r < 0.6 else stone
	if dist < mid_radius:
		if r < 0.4:
			return wood
		return stone if r < 0.75 else essence_faint
	if r < 0.3:
		return stone
	if r < 0.6:
		return essence_faint
	return essence_bright if r < 0.85 else essence_radiant


func _amount_for(dist: float) -> int:
	var t := clampf(dist / world_extent, 0.0, 1.0)
	return int(roundf(lerpf(float(near_amount), float(far_amount), t)))


func _texture_for(material: MaterialType) -> Texture2D:
	match material.id:
		&"wood":
			return tree_texture
		&"stone":
			return rock_texture
		_:
			return wisp_texture


# Snap to a cell centre so a node and its grid cell line up exactly.
func _snap(pos: Vector2) -> Vector2:
	var cell := _cell(pos)
	return Vector2(cell) * CELL_SIZE + Vector2(CELL_SIZE, CELL_SIZE) / 2.0


func _cell(pos: Vector2) -> Vector2i:
	return Vector2i((pos / CELL_SIZE).floor())


# y == 0 is the guaranteed clear corridor from the spawn openings to the tower
# heart; keeping every grid-solid thing off it means a path always exists.
func _blocked(cell: Vector2i) -> bool:
	return cell.y == 0 or _used.has(cell)
