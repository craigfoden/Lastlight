class_name WorldGen3D
extends Node3D
## Deterministic 3D world populator — the port of the 2D WorldGen. From the
## same fixed seed it scatters the same layout: the rng call sequence is
## identical and every distance is the 2D pixel value divided by the 32 px
## cell exactly, so the 3D map is cell-for-cell the 2D map. Runs identically
## on every peer and is never synced; resource *stock* still syncs through
## ResourceNode3D's own RPC lane, which resolves by NodePath — the
## `Res_%d`/`Prop_%d` names below are that contract (see GOTCHAS).
##
## The row of cells at y == 0 (grid terms; world z in [0, 1)) stays clear so a
## path from the spawn openings to the tower heart always exists.

const ResourceNodeScene := preload("res://scenes/world3d/resource_node_3d.tscn")
const SceneryPropScene := preload("res://scenes/world3d/scenery_prop_3d.tscn")

## Baked constant, not randomised per run: every peer must generate the same
## world. A per-run seed would have to be synced before generation — a later
## map-generation step (see ROADMAP), not this one.
@export var world_seed := 20260713

## All radii are the 2D pixel radii / 32 — exact binary divisions, which keeps
## the float math (and therefore every cell choice) identical to the 2D game.
@export var plaza_radius := 4.6875
@export var safe_radius := 15.0
@export var mid_radius := 62.5
@export var world_extent := 93.75

@export_group("Resources")
@export var wood: MaterialType
@export var stone: MaterialType
@export var essence_faint: MaterialType
@export var essence_bright: MaterialType
@export var essence_radiant: MaterialType
@export var tree_scene: PackedScene
@export var rock_scene: PackedScene
@export var wisp_scene: PackedScene
## How many resource nodes to scatter (some rolls land on blocked cells and
## are skipped, same as 2D).
@export var resource_count := 380
## Stock on the closest nodes vs the furthest (lerped by distance).
@export var near_amount := 14
@export var far_amount := 5

@export_group("Scenery")
@export var solid_scenes: Array[PackedScene] = []
@export var decor_textures: Array[Texture2D] = []
@export var scenery_count := 460
## Share of scenery that is solid cover (the rest is flat decor).
@export var solid_share := 0.45

var _used := {}  # cell (Vector2i) -> true; resources + solid props (one per cell)
var _layout := PackedStringArray()  # per-node summary; hashed for the determinism smoke


func _ready() -> void:
	# Runs on host and clients alike; identical seed -> identical world. The
	# layout hash printed below must match on every peer — the smoke tests'
	# cheap cross-peer determinism check.
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	_scatter_resources(rng)
	_scatter_scenery(rng)
	print("[WorldGen3D] Populated: %d resources, %d scenery props (seed %d, layout hash %d)"
			% [resource_count, scenery_count, world_seed, hash("|".join(_layout))])


func _scatter_resources(rng: RandomNumberGenerator) -> void:
	for i in resource_count:
		var pos := _ring_point(rng, plaza_radius, world_extent)
		var cell := _cell(pos)
		if _blocked(cell):
			continue
		_used[cell] = true
		var dist := pos.length()
		var material := _material_for(dist, rng)
		var node := ResourceNodeScene.instantiate() as ResourceNode3D
		node.name = "Res_%d" % i
		node.position = _snap(cell)
		node.material_type = material
		node.starting_amount = _amount_for(dist)
		node.visual_scene = _visual_for(material)
		add_child(node)
		_layout.append("%s:%s:%s" % [node.name, material.id, cell])


func _scatter_scenery(rng: RandomNumberGenerator) -> void:
	for i in scenery_count:
		var solid := rng.randf() < solid_share
		# Solids stay out of the safe ring; decor may dress it (grass etc.).
		var inner := safe_radius if solid else plaza_radius
		var pos := _ring_point(rng, inner, world_extent)
		if solid and solid_scenes.is_empty():
			continue
		if not solid and decor_textures.is_empty():
			continue
		var pick := rng.randi()
		var cell := _cell(pos)
		if solid:
			if _blocked(cell):
				continue
			_used[cell] = true
		var prop := SceneryPropScene.instantiate() as SceneryProp3D
		prop.name = "Prop_%d" % i
		prop.position = _snap(cell)
		prop.solid = solid
		if solid:
			prop.visual_scene = solid_scenes[pick % solid_scenes.size()]
		else:
			prop.decal_texture = decor_textures[pick % decor_textures.size()]
		add_child(prop)
		_layout.append("%s:%s:%d" % [prop.name, cell, int(solid)])


# Uniform-in-annulus sampling so props spread evenly instead of clumping
# toward the centre. Identical math to the 2D WorldGen, in cell units.
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


func _visual_for(material: MaterialType) -> PackedScene:
	match material.id:
		&"wood":
			return tree_scene
		&"stone":
			return rock_scene
		_:
			return wisp_scene


# Cell centre on the ground plane — the 3D twin of the 2D `cell * 32 + 16` snap.
func _snap(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)


# Positions are already in cell units, so a cell is just the floor.
func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(pos.floor())


# y == 0 is the guaranteed clear corridor from the spawn openings to the tower
# heart; keeping every grid-solid thing off it means a path always exists.
func _blocked(cell: Vector2i) -> bool:
	return cell.y == 0 or _used.has(cell)
