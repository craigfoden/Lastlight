class_name WorldGen
extends Node3D
## Deterministic 3D world populator. From one seed it lays out the whole map —
## approach openings and their corridors, then biomes, then camps, then
## resources, then scenery — identically on every peer, and none of it is
## synced. Node *state* still syncs through each node's own RPC lane, which
## resolves by NodePath, so the deterministic `Camp_%d`/`Res_%d`/`Prop_%d` names
## below are that contract (see GOTCHAS).
##
## **What the seed actually decides.** Until session 18 the seed shuffled props
## and nothing else: every run had the same two openings due east and west, the
## same uniform scatter, and the same number of camps. Now the seed chooses
##  * how many ways the night comes in, from where, and how far out they start
##    (`_roll_openings`) — and therefore which lanes the defence has to cover;
##  * what *country* each stretch of the wilds is (`_roll_biomes`) — a Voronoi
##    partition over BiomeType, which reweights what grows there, how thickly,
##    and what colour the ground reads as;
##  * how rich this particular world is at all (`density_jitter`), and how many
##    camps stand in it (`camp_count_jitter`).
## The rarity-by-distance bands are deliberately NOT among them: they are what
## the whole economy is balanced against, and a run whose map hands out Radiant
## Essence at the village would not be a different map, it would be a different
## game (see `_material_for`).
##
## Order matters and is load-bearing. Openings come first because their
## corridors are the one part of the map nothing else may touch; biomes second
## because both scatters ask what country they are standing in; camps third
## because they are the only content with a footprint, and reserving a whole
## site up front is what lets a camp keep its courtyard clear.
##
## Camps are a split responsibility and this is the half that has no state:
## WorldGen decides *where* a camp is and stamps its ruins; Camp itself owns the
## garrison and the cache lock, because guards are host-simulated Enemies and
## cannot come from a deterministic local scatter. See camp.gd.

const ResourceNodeScene := preload("res://scenes/world/resource_node.tscn")
const SceneryPropScene := preload("res://scenes/world/scenery_prop.tscn")

## The seed this run was generated from, for logs and the determinism hash. It
## is *given*, never chosen here: the host rolls one per run and every client
## builds its world only once that number has arrived (game.gd). Generation is
## driven by `generate()` rather than `_ready()` for exactly that reason — a
## client that generated on its own would have a different map from the host,
## and every harvest RPC resolves by node path (see GOTCHAS).
var world_seed := 0

## Where the night comes in from, decided per run. The Game scene reads both:
## cells become the build grid's permanently-reserved opening cells, positions
## become the WaveDirector's spawn points. Before session 18 these were two
## fixed Marker3D nodes in game.tscn; a per-run map cannot have its approaches
## authored in the scene, because the lane has to be *cleared* by the same pass
## that decides where it runs.
var opening_cells: Array[Vector2i] = []
var opening_positions: Array[Vector3] = []

## Biome sites, as parallel arrays: world-XZ centre and the country it seeds.
## A cell belongs to the nearest site (`biome_for`). Read by the ground shader
## too, so what you see underfoot and what you harvest there agree.
var biome_sites := PackedVector2Array()
var biome_kinds: Array[BiomeType] = []

## All radii are the 2D pixel radii / 32 — exact binary divisions, which keeps
## the float math (and therefore every cell choice) identical to the 2D game.
@export var plaza_radius := 4.6875
@export var safe_radius := 15.0
@export var mid_radius := 62.5
@export var world_extent := 93.75

@export_group("Openings")
## How many ways in the night has, rolled per run. Two is the old map; four is a
## siege from every quarter with the same living-cap spread across it, so this is
## a shape dial rather than a difficulty one — but it has never been played, and
## it is the first number to look at if a run feels indefensible.
@export var opening_count_min := 2
@export var opening_count_max := 4
## Ring the openings sit on, in cells. Jittered per run: a nearer opening means
## a shorter march and less time for towers to work on the horde. Kept well
## inside `world_extent` so the outer ring stays daytime territory.
@export var opening_radius_min := 46.0
@export var opening_radius_max := 58.0
## How far an opening may slide off its even share of the compass, as a fraction
## of the gap between neighbours. Zero would give perfectly symmetrical
## approaches, which read as authored rather than found.
@export var opening_angle_jitter := 0.3
## Chebyshev radius of the clearing kept around the tower's heart, in cells.
## Covers the tower's own 2x2 footprint plus a skirt, so a corridor arriving
## from the north always has a free way around the tower it cannot walk through.
@export var heart_clearance := 3

@export_group("Resources")
@export var wood: MaterialType
@export var stone: MaterialType
@export var essence_faint: MaterialType
@export var essence_bright: MaterialType
@export var essence_radiant: MaterialType
@export var tree_scene: PackedScene
@export var rock_scene: PackedScene
@export var wisp_scene: PackedScene
## How many resource *rolls* to make. Not the node count: a roll is skipped if it
## lands on a blocked cell (always was) or if the biome it landed in is too thin
## to keep it (`BiomeType.resource_density`, new in session 18). The log below
## prints what was actually placed, which is the number worth reading.
@export var resource_count := 520
## Chops needed to fell the closest nodes vs the furthest (lerped by distance).
## This is work, not income — see `yield_per_node`.
@export var near_amount := 14
@export var far_amount := 5
## What felling any one node pays into the pool, whatever it cost to fell.
@export var yield_per_node := 4

@export_group("Biomes")
## How many stretches of country the wilds are divided into. Fewer, larger
## biomes read as regions you travel between; more, smaller ones read as noise.
@export var biome_site_count_min := 4
@export var biome_site_count_max := 7
## Innermost radius a biome site may sit at, in cells. The village and its
## immediate surroundings are deliberately biome-free: home is home on every map.
@export var biome_inner_radius := 22.0

@export_group("Camps")
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
## Per-run swing on each camp type's `site_count`, in sites. One world has four
## bandit camps and the next has two — which is the difference between a day
## loop with a queue of work and one with a choice about which site is worth it.
@export var camp_count_jitter := 1

@export_group("Scenery")
@export var solid_scenes: Array[PackedScene] = []
@export var decor_textures: Array[Texture2D] = []
@export var scenery_count := 640
## Share of scenery that is solid cover (the rest is flat decor).
@export var solid_share := 0.45

@export_group("Density")
## Per-run swing on the resource and scenery roll counts, as a fraction. Rolled
## once per run and applied to both, so a world is uniformly rich or uniformly
## picked-over rather than rich in trees and bare of rocks.
@export var density_jitter := 0.18

## The camp roster, in placement order. Read straight off the `Camps` registry
## rather than exported into game.tscn, for the same reason `Buildings` is
## (session 17): a roster that only exists inside a scene file cannot be read by
## anything outside it.
var camp_types: Array[CampType] = Camps.ALL

## The biome roster. Same rule as `camp_types`.
var biome_types: Array[BiomeType] = Biomes.ALL

var _used := {}  # cell (Vector2i) -> true; camps + resources + solid props (one per cell)
## Cells no solid thing may ever occupy: the corridors from each opening to the
## tower's heart, plus the clearing around the heart itself. This replaces the
## old "the y == 0 row is kept clear" rule, which only worked because the
## openings were nailed to that row.
var _corridor := {}
## Centre cell of every camp already placed, for the separation rule.
var _camp_centers: Array[Vector2i] = []
var _layout := PackedStringArray()  # per-node summary; hashed for the determinism smoke
## Highest density any biome asks for, per kind. Scatter acceptance is measured
## against these, so a `resource_density` of 1.3 really is twice as thick as a
## 0.65 — see `_accepts_density`.
var _max_resource_density := 1.0
var _max_solid_density := 1.0
var _max_decor_density := 1.0


## Lays out the world. Called by the Game scene on host and clients alike, with
## the same seed on both; identical seed -> identical world. `heart` is the cell
## enemies path to (game.gd owns it, and the corridors have to end there).
## The layout hash printed below must match on every peer — the smoke tests'
## cheap cross-peer determinism check, and now also the check that the seed
## itself travelled.
func generate(seed_value: int, heart: Vector2i) -> void:
	world_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	_measure_densities()
	# One richness roll for the whole world (see `density_jitter`).
	var richness := 1.0 + rng.randf_range(-density_jitter, density_jitter)
	_roll_openings(rng, heart)
	_roll_biomes(rng)
	var camps := _scatter_camps(rng)
	var resources := _scatter_resources(rng, richness)
	var props := _scatter_scenery(rng, richness)
	print("[WorldGen] Populated: %d camps, %d resources, %d scenery props "
			% [camps, resources, props]
			+ "(seed %d, %d openings, %d biomes, richness %.2f, layout hash %d)"
			% [world_seed, opening_cells.size(), biome_sites.size(), richness,
			hash("|".join(_layout))])
	print("[WorldGen] Openings: %s" % [opening_cells])
	print("[WorldGen] Biomes: %s" % [_biome_summary()])


## Which country a point on the ground plane belongs to, or null for the
## village and its surroundings (no site is ever placed within
## `biome_inner_radius`, but a cell that near is still nearest to *something* —
## so the village is decided by distance here, not by the partition).
func biome_for(point: Vector2) -> BiomeType:
	if biome_sites.is_empty() or point.length() < safe_radius:
		return null
	var best := 0
	var best_dist := INF
	for i in biome_sites.size():
		var dist := point.distance_squared_to(biome_sites[i])
		if dist < best_dist:
			best_dist = dist
			best = i
	return biome_kinds[best]


# --- openings & corridors ----------------------------------------------------

# Where the night comes in. Evenly spread around the compass so no run can put
# every approach on one side of the village, then jittered so the spread never
# reads as drawn with a protractor.
func _roll_openings(rng: RandomNumberGenerator, heart: Vector2i) -> void:
	var count := rng.randi_range(opening_count_min, opening_count_max)
	var spacing := TAU / float(count)
	var base := rng.randf() * TAU
	for i in count:
		var angle := base + spacing * i \
				+ rng.randf_range(-spacing, spacing) * opening_angle_jitter
		var radius := rng.randf_range(opening_radius_min, opening_radius_max)
		var point := Vector2(radius, 0).rotated(angle)
		var cell := _cell(point)
		opening_cells.append(cell)
		opening_positions.append(_snap(cell))
		_layout.append("Opening_%d:%s" % [i, cell])
		for lane_cell in _corridor_cells(cell, heart):
			_corridor[lane_cell] = true
	# The tower's own footprint is solid and cannot be walked through, so the
	# corridors have to arrive at a heart that has room around it. Clearing a
	# block rather than the exact footprint keeps this independent of where
	# game.gd happens to put the tower.
	for dx in range(-heart_clearance, heart_clearance + 1):
		for dz in range(-heart_clearance, heart_clearance + 1):
			_corridor[heart + Vector2i(dx, dz)] = true


# The cells one lane occupies. Walked at half-cell steps rather than rasterised
# with Bresenham because the grid is ORTHOGONAL-ONLY (AStarGrid2D,
# DIAGONAL_MODE_NEVER): a line that steps diagonally leaves two solid cells
# touching at a corner, which looks like a corridor and is not one. Every
# diagonal step therefore has its elbow filled in.
func _corridor_cells(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [from]
	var delta := Vector2(to - from)
	var steps := int(maxf(absf(delta.x), absf(delta.y))) * 2
	if steps <= 0:
		return cells
	var previous := from
	for i in range(1, steps + 1):
		var point := Vector2(from) + delta * (float(i) / float(steps))
		var cell := Vector2i(roundi(point.x), roundi(point.y))
		if cell == previous:
			continue
		if cell.x != previous.x and cell.y != previous.y:
			cells.append(Vector2i(cell.x, previous.y))
		cells.append(cell)
		previous = cell
	return cells


# --- biomes ------------------------------------------------------------------

func _roll_biomes(rng: RandomNumberGenerator) -> void:
	if biome_types.is_empty():
		return
	var count := rng.randi_range(biome_site_count_min, biome_site_count_max)
	var total_weight := 0.0
	for biome in biome_types:
		total_weight += maxf(biome.weight, 0.0)
	for i in count:
		var point := _ring_point(rng, biome_inner_radius, world_extent)
		var pick := rng.randf() * total_weight
		var chosen := biome_types[biome_types.size() - 1]
		for biome in biome_types:
			pick -= maxf(biome.weight, 0.0)
			if pick <= 0.0:
				chosen = biome
				break
		biome_sites.append(point)
		biome_kinds.append(chosen)
		_layout.append("Biome_%d:%s:%s" % [i, chosen.id, _cell(point)])


# Highest density asked for by any biome, per scatter kind. Acceptance is a
# ratio against these (see `_accepts_density`) so a biome above 1.0 is genuinely
# denser than the baseline instead of silently clamping to it.
func _measure_densities() -> void:
	_max_resource_density = 1.0
	_max_solid_density = 1.0
	_max_decor_density = 1.0
	for biome in biome_types:
		_max_resource_density = maxf(_max_resource_density, biome.resource_density)
		_max_solid_density = maxf(_max_solid_density, biome.solid_density)
		_max_decor_density = maxf(_max_decor_density, biome.decor_density)


# Rejection sampling: always consumes exactly one draw, whatever it answers, so
# the rng sequence (and therefore the whole map) stays a pure function of the
# seed no matter which biome a roll landed in.
func _accepts_density(rng: RandomNumberGenerator, density: float, ceiling: float) -> bool:
	return rng.randf() * maxf(ceiling, 0.0001) < density


func _biome_summary() -> Dictionary:
	var counts := {}
	for biome in biome_kinds:
		counts[biome.id] = int(counts.get(biome.id, 0)) + 1
	return counts


# --- camps -------------------------------------------------------------------

# Camps go down after the openings and biomes (see the class doc). Returns how
# many were actually placed — a site that could not be found after
# `camp_site_attempts` rolls is skipped and logged rather than retried forever.
func _scatter_camps(rng: RandomNumberGenerator) -> int:
	var placed := 0
	for type: CampType in camp_types:
		var sites := maxi(type.site_count
				+ rng.randi_range(-camp_count_jitter, camp_count_jitter), 1)
		for _site in sites:
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


# A site is clear when the whole footprint is in bounds, off every corridor,
# clear of anything already placed, and far enough from every camp already
# standing.
func _camp_site_clear(center: Vector2i, type: CampType) -> bool:
	var r := type.footprint_radius
	for other in _camp_centers:
		if absi(other.x - center.x) < camp_separation + r * 2 \
				and absi(other.y - center.y) < camp_separation + r * 2:
			return false
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var cell := center + Vector2i(dx, dz)
			# Straddling a lane would leave the camp with a hole punched through
			# both its walls — and, worse, would let the site's own perimeter
			# stand in the only guaranteed path to the tower.
			if _used.has(cell) or _corridor.has(cell):
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


# --- scatter -----------------------------------------------------------------

func _scatter_resources(rng: RandomNumberGenerator, richness: float) -> int:
	var placed := 0
	var rolls := int(roundf(resource_count * richness))
	for i in rolls:
		var pos := _ring_point(rng, plaza_radius, world_extent)
		var biome := biome_for(pos)
		var density := biome.resource_density if biome != null else 1.0
		if not _accepts_density(rng, density, _max_resource_density):
			continue
		var cell := _cell(pos)
		if _blocked(cell):
			continue
		_used[cell] = true
		var dist := pos.length()
		var material := _material_for(dist, rng, biome)
		var node := ResourceNodeScene.instantiate() as ResourceNode
		node.name = "Res_%d" % i
		node.position = _snap(cell)
		node.material_type = material
		node.starting_amount = _amount_for(dist)
		node.depleted_yield = yield_per_node
		node.visual_scene = _visual_for(material)
		add_child(node)
		_layout.append("%s:%s:%s" % [node.name, material.id, cell])
		placed += 1
	return placed


func _scatter_scenery(rng: RandomNumberGenerator, richness: float) -> int:
	var placed := 0
	var rolls := int(roundf(scenery_count * richness))
	for i in rolls:
		var solid := rng.randf() < solid_share
		# Solids stay out of the safe ring; decor may dress it (grass etc.).
		var inner := safe_radius if solid else plaza_radius
		var pos := _ring_point(rng, inner, world_extent)
		if solid and solid_scenes.is_empty():
			continue
		if not solid and decor_textures.is_empty():
			continue
		var biome := biome_for(pos)
		var density := 1.0
		if biome != null:
			density = biome.solid_density if solid else biome.decor_density
		if not _accepts_density(rng, density,
				_max_solid_density if solid else _max_decor_density):
			continue
		var pick := rng.randi()
		var cell := _cell(pos)
		if solid:
			if _blocked(cell):
				continue
			_used[cell] = true
		elif _corridor.has(cell) and not solid:
			# Decor blocks nothing, but a tuft of grass in the middle of the lane
			# the shader draws as a beaten path just reads as a mistake.
			continue
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
		placed += 1
	return placed


# Uniform-in-annulus sampling so props spread evenly instead of clumping
# toward the centre. Identical math to the 2D WorldGen, in cell units.
func _ring_point(rng: RandomNumberGenerator, r_min: float, r_max: float) -> Vector2:
	var radius := sqrt(rng.randf() * (r_max * r_max - r_min * r_min) + r_min * r_min)
	var angle := rng.randf() * TAU
	return Vector2(radius, 0).rotated(angle)


# What grows at `dist` from the tower, in the country `biome`. Distance picks
# the BAND — that is the rarity curve the economy is balanced on and no biome
# may move it — and the biome reweights within it.
#
# Radiant Essence is exempt from the reweighting entirely. Its 4 % ambient share
# is the dial that decides whether tier-III towers are earned by clearing a
# barrow or found by walking (session 15), and handing a leyfield the power to
# multiply it would quietly undo that in one run out of six.
func _material_for(dist: float, rng: RandomNumberGenerator,
		biome: BiomeType) -> MaterialType:
	var options: Array[MaterialType] = []
	var weights: Array[float] = []
	if dist < safe_radius:
		options = [wood, stone]
		weights = [0.6, 0.4]
	elif dist < mid_radius:
		options = [wood, stone, essence_faint]
		weights = [0.4, 0.35, 0.25]
	else:
		options = [stone, essence_faint, essence_bright]
		weights = [0.3, 0.3, 0.36]
	# The band's weights sum to 1 minus whatever Radiant holds back; biomes
	# redistribute that remainder among themselves and can never enlarge it.
	var share := 0.0
	for weight in weights:
		share += weight
	if biome != null:
		var total := 0.0
		for i in options.size():
			weights[i] *= float(biome.material_weights.get(options[i].id, 1.0))
			total += weights[i]
		if total <= 0.0:
			return options[0]
		for i in weights.size():
			weights[i] *= share / total
	var roll := rng.randf()
	for i in options.size():
		roll -= weights[i]
		if roll <= 0.0:
			return options[i]
	# Only reachable in the outer band, where the leftover share IS Radiant.
	return essence_radiant if dist >= mid_radius else options[options.size() - 1]


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


# The corridors from every opening to the tower's heart are the guaranteed
# clear lanes; keeping every grid-solid thing off them means a path always
# exists, however the openings fell this run.
func _blocked(cell: Vector2i) -> bool:
	return _corridor.has(cell) or _used.has(cell)
