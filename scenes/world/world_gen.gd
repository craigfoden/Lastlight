class_name WorldGen
extends Node3D
## Deterministic 3D world populator. From one seed it lays out the whole map —
## camps first, then resources, then scenery — identically on every peer, and
## none of it is synced. Node *state* still syncs through each node's own
## RPC lane, which resolves by NodePath, so the deterministic
## `Camp_%d`/`Res_%d`/`Prop_%d` names below are that contract (see GOTCHAS).
##
## Camps are stamped **before** the scatter passes because they are the only
## content with a footprint: reserving a whole site up front is what lets a camp
## keep its courtyard clear, and it costs the scatter nothing but a handful of
## skipped rolls. (This is also why the layout is no longer cell-for-cell the
## 2D game's — the rng sequence now starts with the camps.)
##
## Camps are a split responsibility and this is the half that has no state:
## WorldGen decides *where* a camp is and stamps its ruins; Camp itself owns the
## garrison and the cache lock, because guards are host-simulated Enemies and
## cannot come from a deterministic local scatter. See camp.gd.
##
## The row of cells at y == 0 (grid terms; world z in [0, 1)) stays clear so a
## path from the spawn openings to the tower heart always exists.

const ResourceNodeScene := preload("res://scenes/world/resource_node.tscn")
const SceneryPropScene := preload("res://scenes/world/scenery_prop.tscn")

## The seed this run was generated from, for logs and the determinism hash. It
## is *given*, never chosen here: the host rolls one per run and every client
## builds its world only once that number has arrived (game.gd). Generation is
## driven by `generate()` rather than `_ready()` for exactly that reason — a
## client that generated on its own would have a different map from the host,
## and every harvest RPC resolves by node path (see GOTCHAS).
var world_seed := 0

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
## Chops needed to fell the closest nodes vs the furthest (lerped by distance).
## This is work, not income — see `yield_per_node`.
@export var near_amount := 14
@export var far_amount := 5
## What felling any one node pays into the pool, whatever it cost to fell.
@export var yield_per_node := 4

@export_group("Camps")
## The camp roster, in placement order. Recipe: a new camp .tres goes here.
@export var camp_types: Array[CampType] = []
## Ruined-wall looks stamped around a camp footprint (picked per cell).
@export var camp_wall_scenes: Array[PackedScene] = []
## The cache mesh every camp puts at its centre.
@export var cache_visual: PackedScene
## Clear cells kept between two camp footprints, so sites read as separate
## places rather than one sprawling ruin.
@export var camp_separation := 8
## How many times a camp site is re-rolled before that camp is given up on.
## Bounded so generation can never hang; a skipped camp is logged.
@export var camp_site_attempts := 40

@export_group("Scenery")
@export var solid_scenes: Array[PackedScene] = []
@export var decor_textures: Array[Texture2D] = []
@export var scenery_count := 460
## Share of scenery that is solid cover (the rest is flat decor).
@export var solid_share := 0.45

var _used := {}  # cell (Vector2i) -> true; camps + resources + solid props (one per cell)
## Centre cell of every camp already placed, for the separation rule.
var _camp_centers: Array[Vector2i] = []
var _layout := PackedStringArray()  # per-node summary; hashed for the determinism smoke


## Lays out the world. Called by the Game scene on host and clients alike, with
## the same seed on both; identical seed -> identical world. The layout hash
## printed below must match on every peer — the smoke tests' cheap cross-peer
## determinism check, and now also the check that the seed itself travelled.
func generate(seed_value: int) -> void:
	world_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var camps := _scatter_camps(rng)
	_scatter_resources(rng)
	_scatter_scenery(rng)
	print("[WorldGen] Populated: %d camps, %d resources, %d scenery props (seed %d, layout hash %d)"
			% [camps, resource_count, scenery_count, world_seed, hash("|".join(_layout))])


# Camps go down first (see the class doc). Returns how many were actually
# placed — a site that could not be found after `camp_site_attempts` rolls is
# skipped and logged rather than retried forever.
func _scatter_camps(rng: RandomNumberGenerator) -> int:
	var placed := 0
	for type: CampType in camp_types:
		for _site in type.site_count:
			var center := Vector2i.ZERO
			var found := false
			for _attempt in camp_site_attempts:
				center = _cell(_ring_point(rng, type.radius_min, type.radius_max))
				if _camp_site_clear(center, type):
					found = true
					break
			if not found:
				print("[WorldGen] No room for a %s after %d attempts - skipped"
						% [type.id, camp_site_attempts])
				continue
			_build_camp(rng, type, center, placed)
			placed += 1
	return placed


# A site is clear when the whole footprint is in bounds, off the guaranteed
# corridor, clear of anything already placed, and far enough from every camp
# already standing.
func _camp_site_clear(center: Vector2i, type: CampType) -> bool:
	var r := type.footprint_radius
	# Straddling the y == 0 corridor would leave a camp with a hole punched
	# through both its walls; keep whole sites off it instead.
	if absi(center.y) <= r:
		return false
	for other in _camp_centers:
		if absi(other.x - center.x) < camp_separation + r * 2 \
				and absi(other.y - center.y) < camp_separation + r * 2:
			return false
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var cell := center + Vector2i(dx, dz)
			if _used.has(cell):
				return false
			# The footprint must sit inside the map, and clear of the village.
			var from_center := Vector2(cell.x + 0.5, cell.y + 0.5)
			if from_center.length() > world_extent or from_center.length() < safe_radius:
				return false
	return true


# Stamp one camp: reserve the whole footprint, ring it with ruined walls (minus
# a doorway), and drop the Camp node — which builds its own cache — at the
# middle. The interior is deliberately left empty: a camp's courtyard is where
# its garrison stands, and Camp posts guards there without re-checking for
# walls, on the strength of this.
func _build_camp(rng: RandomNumberGenerator, type: CampType, center: Vector2i,
		index: int) -> void:
	var r := type.footprint_radius
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			_used[center + Vector2i(dx, dz)] = true
	# One side of the ring is opened so the camp can be walked into (and out of,
	# by a guard giving chase). Rolled before the stamp loop so the wall picks
	# below stay a single unbroken rng run.
	var door_side := rng.randi() % 4
	var door_offset := rng.randi_range(-r, r - 1)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if maxi(absi(dx), absi(dz)) != r:
				continue  # interior: courtyard, left clear
			if _is_doorway(dx, dz, r, door_side, door_offset):
				continue
			var cell := center + Vector2i(dx, dz)
			var pick := rng.randi()
			if camp_wall_scenes.is_empty():
				continue
			var prop := SceneryPropScene.instantiate() as SceneryProp
			prop.name = "CampWall_%d_%d_%d" % [index, dx + r, dz + r]
			prop.position = _snap(cell)
			prop.solid = true
			prop.visual_scene = camp_wall_scenes[pick % camp_wall_scenes.size()]
			add_child(prop)
			_layout.append("%s:%s" % [prop.name, cell])
	_camp_centers.append(center)
	var camp := Camp.new()
	camp.name = "Camp_%d" % index
	camp.position = _snap(center)
	camp.configure(type, cache_visual)
	add_child(camp)
	_layout.append("%s:%s:%s" % [camp.name, type.id, center])


# Two adjacent cells on one side of the ring. Corners can be part of it; a camp
# with a corner knocked out is still a camp.
func _is_doorway(dx: int, dz: int, r: int, side: int, offset: int) -> bool:
	var along := 0
	match side:
		0:
			if dz != -r:
				return false
			along = dx
		1:
			if dz != r:
				return false
			along = dx
		2:
			if dx != -r:
				return false
			along = dz
		_:
			if dx != r:
				return false
			along = dz
	return along == offset or along == offset + 1


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
		node.position = _snap(cell)
		node.material_type = material
		node.starting_amount = _amount_for(dist)
		node.depleted_yield = yield_per_node
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
		var prop := SceneryPropScene.instantiate() as SceneryProp
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
	# Radiant essence is deliberately almost absent from the ambient scatter: it
	# is what camps are *for*, and tier-III towers are meant to be gated on
	# clearing one rather than on walking far enough. The 4 % left here is a
	# safety valve, not a supply — a party that ignores camps should feel the
	# tier out of reach, not find it hard-locked (session 15; the dial to turn if
	# camps prove too punishing is this number, not the camp loot).
	return essence_bright if r < 0.96 else essence_radiant


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
