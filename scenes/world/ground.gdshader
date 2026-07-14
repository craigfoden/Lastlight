shader_type spatial;
// The ground carries the village glow, exactly like the 2D game's VillageGlow
// gradient sprite over its dark base polygon: bright near the tower (the
// world origin), fading to the dark wilds by `dark_radius`. This is albedo
// only — the shader stays fully lit, so the sun, the night ambient, and the
// tower's light pool all still land on top (the 2D CanvasModulate multiplied
// the glow the same way). Radii in cells; 2D parity: glow gone by 16 cells,
// one past the 15-cell safe radius.

uniform vec3 village_color : source_color = vec3(0.24, 0.29, 0.2);
// The day-side brightening comes from the tower's daylight bubble (see
// WorldLight); this painted gradient's job is the DARK side — keeping the
// floor beyond the safe zone genuinely black at night, when the ambient
// would otherwise lift a paler albedo.
uniform vec3 wilds_color : source_color = vec3(0.06, 0.075, 0.055);
// Fully bright inside this distance from the tower...
uniform float glow_radius = 4.0;
// ...fully dark beyond this one.
uniform float dark_radius = 18.0;

void fragment() {
	// The plane is 4 vertices, so the distance must be per-fragment:
	// view-space VERTEX back to world space, distance on the ground plane.
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(world_pos.xz);
	ALBEDO = mix(village_color, wilds_color, smoothstep(glow_radius, dark_radius, dist));
	ROUGHNESS = 1.0;
}
