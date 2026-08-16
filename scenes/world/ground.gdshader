shader_type spatial;
// The ground: repeating pixel tiles, blended from village turf to dead wilds
// dirt with distance from the tower, exactly like the 2D game's VillageGlow
// gradient over its dark base polygon. This is albedo only — the shader stays
// fully lit, so the sun, the night ambient, and the tower's light pool all
// still land on top (the 2D CanvasModulate multiplied the glow the same way).
// Radii in cells; 2D parity: glow gone by 16 cells, one past the 15-cell safe
// radius.
//
// Three things are drawn on top of that gradient, and all three come from the
// map WorldGen actually generated (Ground.setup pushes them):
//
//  * **Biomes.** A Voronoi partition over up to MAX_BIOMES sites; each site
//    tints the wilds tile its country's colour. Cheap enough to do per fragment
//    at this site count, and it means the ground you are standing on tells you
//    what grows there before you have walked far enough to count the trees.
//  * **Approach roads.** The corridors from each opening to the tower's heart
//    are the one part of the map guaranteed to stay clear of solids, so they are
//    also the one part that can honestly be drawn as a beaten path — and the
//    path is the game quietly telling you where the horde will come from.
//  * **The village boundary.** A trodden ring at the safe radius. Before it,
//    nothing in the world marked where the light — and the roamers' refusal to
//    cross it — actually ended.
//
// All three sample the same path tile, so the world has one kind of bare
// ground rather than three.

// Every tile must be sampled with NEAREST and REPEAT: the whole look depends on
// hard texel edges, and a filtered pixel tile is just a blurry pixel tile.
uniform sampler2D village_tile : source_color, filter_nearest, repeat_enable;
uniform sampler2D wilds_tile : source_color, filter_nearest, repeat_enable;
uniform sampler2D path_tile : source_color, filter_nearest, repeat_enable;

// Tint over each tile, so the gradient can still be tuned without redrawing
// anything. The wilds side is the one that matters: it keeps the floor beyond
// the safe zone genuinely dark at night, when the ambient would otherwise lift
// a paler albedo. (The day-side brightening comes from the tower's daylight
// bubble — see WorldLight.)
uniform vec3 village_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 wilds_color : source_color = vec3(0.62, 0.66, 0.6);
// Fully village inside this distance from the tower...
uniform float glow_radius = 4.0;
// ...fully wilds beyond this one.
uniform float dark_radius = 18.0;

// World size of one tile. 32 texels at the 0.036-unit texel every sprite in the
// game uses (PixelRender.texel_world_size), so one ground texel lands on one
// rendered pixel just as one sprite texel does — which is the whole reason the
// two halves of the art look like one game. Change it and the ground starts
// shimmering as the camera moves while the sprites stay steady.
uniform float tile_world_size = 1.152;

// How far the per-cell jitter can lift or drop a tile's brightness. A tile this
// small repeats a couple of hundred times across the map, and the eye finds
// that grid instantly; varying whole tiles slightly breaks it up far more
// cheaply than a bigger tile or a second variant would. Too much and the ground
// reads as a checkerboard, which is the same failure the other way.
uniform float tile_jitter = 0.07;

// Biome sites in world XZ, and the colour each one tints the wilds tile. Sized
// one above WorldGen's `biome_site_count_max`; unused slots are parked far off
// the map so they can never win the nearest-site test.
const int MAX_BIOMES = 8;
uniform vec2 biome_sites[MAX_BIOMES];
uniform vec3 biome_colors[MAX_BIOMES];
uniform int biome_count = 0;
// How far into the village the biome tints reach. Home reads the same on every
// map, so the tint fades in across this band rather than at a hard line.
uniform float biome_inner_fade = 15.0;
// How wide the dithered no-man's-land between two biomes is, in cells. Whole
// tiles are traded across it, so this is measured in tiles you can count, not
// in a gradient.
uniform float biome_blend = 5.0;

// Approach roads, as line segments from each opening to the heart. Sized to
// WorldGen's `opening_count_max`.
const int MAX_PATHS = 4;
uniform vec2 path_from[MAX_PATHS];
uniform vec2 path_to[MAX_PATHS];
uniform int path_count = 0;
// Half-width of a road, in cells. Wider than the one-cell corridor WorldGen
// actually keeps clear: a road exactly as wide as its guarantee reads as a
// suspiciously straight line rather than as something walked into the ground.
uniform float path_half_width = 1.3;

// The village boundary ring: where it sits and how wide the trodden band is.
uniform float edge_radius = 15.0;
uniform float edge_width = 0.55;

// Cheap hash -> [0, 1). Value noise per tile, not per fragment: the input is
// the tile index, so a whole tile shifts together.
float hash21(vec2 p) {
	return fract(sin(dot(floor(p), vec2(127.1, 311.7))) * 43758.5453);
}

// Distance from a point to a segment, on the ground plane.
float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float len_sq = dot(ab, ab);
	if (len_sq < 0.0001) {
		return distance(p, a);
	}
	float t = clamp(dot(p - a, ab) / len_sq, 0.0, 1.0);
	return distance(p, a + ab * t);
}

void fragment() {
	// The plane is 4 vertices, so everything here must be per-fragment:
	// view-space VERTEX back to world space, then work on the ground plane.
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 ground = world_pos.xz;
	vec2 tile_uv = ground / tile_world_size;
	float dist = length(ground);

	// Which country this fragment stands in. Nearest site wins — but a straight
	// Voronoi border is a perfectly clean line across a world made of hard
	// texels, and it reads as a seam in the floor. So the two nearest sites are
	// kept and, within `biome_blend` of being tied, the per-tile hash decides
	// which one this tile belongs to: the border comes apart into a crumbling
	// interlock of whole tiles, the same trick the roads' edges use.
	vec3 biome_tint = vec3(1.0);
	if (biome_count > 0) {
		float best = 1.0e9;
		float second = 1.0e9;
		int best_index = 0;
		int second_index = 0;
		for (int i = 0; i < MAX_BIOMES; i++) {
			if (i >= biome_count) {
				break;
			}
			float d = distance(ground, biome_sites[i]);
			if (d < best) {
				second = best;
				second_index = best_index;
				best = d;
				best_index = i;
			} else if (d < second) {
				second = d;
				second_index = i;
			}
		}
		int chosen = best_index;
		// Offset input: sharing the brightness jitter's hash would make the
		// tiles that swap country always the bright ones, and the border would
		// come apart into a visible sparkle.
		if (second - best < biome_blend * hash21(tile_uv + vec2(37.0, 11.0))) {
			chosen = second_index;
		}
		biome_tint = mix(vec3(1.0), biome_colors[chosen],
				smoothstep(biome_inner_fade, biome_inner_fade * 1.6, dist));
	}

	vec3 village = texture(village_tile, tile_uv).rgb * village_color;
	vec3 wilds = texture(wilds_tile, tile_uv).rgb * wilds_color * biome_tint;
	vec3 surface = mix(village, wilds, smoothstep(glow_radius, dark_radius, dist));

	// Roads and the village ring, both drawn in the same bare ground. The
	// coverage test is dithered with the per-tile hash rather than smoothstepped:
	// a soft alpha edge would be the one gradient in a game made of hard texels.
	float road = 1.0e9;
	for (int i = 0; i < MAX_PATHS; i++) {
		if (i >= path_count) {
			break;
		}
		road = min(road, segment_distance(ground, path_from[i], path_to[i]));
	}
	float ring = abs(dist - edge_radius) - edge_width;
	float bare = min(road - path_half_width, ring);
	// Half a tile of dithered fringe, so the edge crumbles into the grass.
	if (bare < (hash21(tile_uv * 2.0) - 0.35) * 0.9) {
		vec3 path = texture(path_tile, tile_uv).rgb;
		// The road takes the local ground's own tint, so it darkens into the
		// wilds and picks up the biome it crosses instead of being a bright
		// stripe laid over the top of everything.
		surface = path * mix(village_color, wilds_color * biome_tint,
				smoothstep(glow_radius, dark_radius, dist));
	}

	ALBEDO = surface * (1.0 + (hash21(tile_uv) - 0.5) * 2.0 * tile_jitter);
	ROUGHNESS = 1.0;
}
