class_name Ground
extends MeshInstance3D
## The world's floor. One plane, one shader — and this script is the only thing
## that tells that shader what world it is drawing.
##
## Before session 18 the ground was a pure function of distance from the tower,
## so it could be authored entirely in game.tscn and needed no script at all.
## Now it draws the map that was actually generated: the biome partition, the
## approach roads, the village boundary. All three come from WorldGen, all three
## are per-run, and none of them is networked — every peer generates the same
## world from the same seed and therefore paints the same floor.
##
## Array uniforms are fixed-size in a shader, so the arrays pushed here are
## always full length: unused biome slots are parked far off the map (they can
## never win the nearest-site test) and unused road slots are zero-length
## segments the loop never reaches, since both loops stop at their count.

## Must match the shader's MAX_BIOMES / MAX_PATHS, which in turn sit one above
## WorldGen's `biome_site_count_max` and at `opening_count_max`.
const MAX_BIOMES := 8
const MAX_PATHS := 4

## Where the padding sites go: far enough outside `world_extent` that no
## fragment on the plane is ever nearest to one.
const OFF_MAP := Vector2(100000.0, 100000.0)


## Called by the Game scene once the world exists (host immediately, client once
## the host's seed has arrived).
func setup(world_gen: WorldGen) -> void:
	var material := mesh.surface_get_material(0) as ShaderMaterial
	if material == null:
		push_warning("[Ground] No ShaderMaterial on the plane — nothing to drive.")
		return

	var sites := PackedVector2Array()
	var colors := PackedVector3Array()
	var biome_count := mini(world_gen.biome_sites.size(), MAX_BIOMES)
	for i in MAX_BIOMES:
		if i < biome_count:
			sites.append(world_gen.biome_sites[i])
			var tint := world_gen.biome_kinds[i].ground_color
			colors.append(Vector3(tint.r, tint.g, tint.b))
		else:
			sites.append(OFF_MAP)
			colors.append(Vector3.ONE)

	# One road per opening, drawn as the straight line the corridor was
	# rasterised from rather than as the cells themselves — the cells are a
	# staircase and the eye reads the line.
	var from := PackedVector2Array()
	var to := PackedVector2Array()
	var heart := Vector2(0.5, 0.5)
	var path_count := mini(world_gen.opening_positions.size(), MAX_PATHS)
	for i in MAX_PATHS:
		if i < path_count:
			var opening := world_gen.opening_positions[i]
			from.append(Vector2(opening.x, opening.z))
			to.append(heart)
		else:
			from.append(Vector2.ZERO)
			to.append(Vector2.ZERO)

	material.set_shader_parameter(&"biome_sites", sites)
	material.set_shader_parameter(&"biome_colors", colors)
	material.set_shader_parameter(&"biome_count", biome_count)
	material.set_shader_parameter(&"biome_inner_fade", world_gen.safe_radius)
	material.set_shader_parameter(&"path_from", from)
	material.set_shader_parameter(&"path_to", to)
	material.set_shader_parameter(&"path_count", path_count)
	material.set_shader_parameter(&"edge_radius", world_gen.safe_radius)
	print("[Ground] Painting %d biome(s) and %d road(s)" % [biome_count, path_count])
