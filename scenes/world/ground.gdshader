shader_type spatial;
// The ground: a repeating pixel tile, blended from village turf to dead wilds
// dirt with distance from the tower, exactly like the 2D game's VillageGlow
// gradient over its dark base polygon. This is albedo only — the shader stays
// fully lit, so the sun, the night ambient, and the tower's light pool all
// still land on top (the 2D CanvasModulate multiplied the glow the same way).
// Radii in cells; 2D parity: glow gone by 16 cells, one past the 15-cell safe
// radius.
//
// Before the tiles, this was a flat two-colour gradient and the largest smooth
// surface in frame — everything else in the game reads as pixel art and the
// floor underneath it did not. The tiles are authored in tools/art (see
// ArtSprites.TILES) and share the one palette.

// Both tiles must be sampled with NEAREST and REPEAT: the whole look depends on
// hard texel edges, and a filtered pixel tile is just a blurry pixel tile.
uniform sampler2D village_tile : source_color, filter_nearest, repeat_enable;
uniform sampler2D wilds_tile : source_color, filter_nearest, repeat_enable;

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

// Cheap hash -> [0, 1). Value noise per tile, not per fragment: the input is
// the tile index, so a whole tile shifts together.
float hash21(vec2 p) {
	return fract(sin(dot(floor(p), vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// The plane is 4 vertices, so everything here must be per-fragment:
	// view-space VERTEX back to world space, then work on the ground plane.
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 tile_uv = world_pos.xz / tile_world_size;
	float dist = length(world_pos.xz);

	vec3 village = texture(village_tile, tile_uv).rgb * village_color;
	vec3 wilds = texture(wilds_tile, tile_uv).rgb * wilds_color;
	vec3 surface = mix(village, wilds, smoothstep(glow_radius, dark_radius, dist));

	ALBEDO = surface * (1.0 + (hash21(tile_uv) - 0.5) * 2.0 * tile_jitter);
	ROUGHNESS = 1.0;
}
