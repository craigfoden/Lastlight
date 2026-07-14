class_name WorldLight
extends Node
## Drives the 3D world's light from the DayNightCycle — the port of the 2D
## CanvasModulate `WorldLight`, grown into "light as gameplay" proper: the
## village's light IS the daylight. The tower projects a large bubble by day
## (everything — props, enemies, ground — falls into gloom the further out you
## venture, because the light literally doesn't reach) while the global sun
## and ambient stay at gloom levels; at dusk the bubble visibly contracts into
## the night pool. Billboard sprites are hand-tinted each frame to match
## (unshaded sprites don't react to lights — this IS their lighting; survival
## tints compose on top, see Player/Enemy.set_light_tint). Runs identically
## on every peer: the cycle is replicated, everything here derives from it.
##
## Dusk and dawn crossfade over the cycle's `transition_time` (the prototype
## snapped at the boundary; at real night lengths the pop is jarring).

## Day sun: arcs from low east to high noon to low west. Deliberately dim —
## it carries direction and shadows, not brightness; the tower's daylight
## bubble is what makes the village bright.
@export var sun_elevation_low := 18.0
@export var sun_elevation_high := 72.0
@export var sun_energy_low := 0.15
@export var sun_energy_high := 0.45
@export var sun_color_noon := Color(1.0, 0.93, 0.82)
@export var sun_color_horizon := Color(1.0, 0.72, 0.5)
## Sun never fully dies at night or shadows pop off; this is "moonlight".
@export var sun_energy_night := 0.02
## Yaw the sun sweeps across the day (degrees, east to west).
@export var sun_yaw_start := -40.0
@export var sun_yaw_sweep := 80.0

@export_group("Sky & ambient")
@export var sky_day := Color("30402a")
@export var sky_horizon := Color("1c2418")
@export var sky_night := Color("0a0e12")
@export var ambient_day := Color("6b7a5e")
@export var ambient_night := Color("2a3448")
@export var ambient_energy_low := 0.12
@export var ambient_energy_high := 0.3
@export var ambient_energy_night := 0.2

@export_group("Tower light")
## By day the tower light is the DAYLIGHT BUBBLE: bright across the village,
## falling off continuously into the wilds. By night it contracts to the pool.
@export var tower_energy_day := 2.4
@export var tower_energy_night := 3.0
@export var tower_range_day := 44.0
@export var tower_range_night := 16.0
## The night pool breathes: +/- this energy on a fixed period (the prototype
## pulsed 3x per night, which at real night lengths is a 60 s swell — too slow
## to read as alive).
@export var tower_pulse_energy := 0.25
@export var tower_pulse_period := 4.0

@export_group("Sprite tint")
@export var tint_noon := Color(1, 1, 1)
@export var tint_horizon := Color(1.0, 0.82, 0.68)
@export var tint_night := Color(0.36, 0.4, 0.55)
## What a sprite fades to outside the light's reach — the billboard twin of
## the mesh world falling out of the bubble.
@export var tint_gloom := Color(0.36, 0.4, 0.55)
## Standing in the tower's pool warms a sprite toward this, strongest at night.
@export var tint_glow := Color(1.0, 0.9, 0.7)
@export var glow_strength_day := 0.35
@export var glow_strength_night := 0.85

var _day_night: DayNightCycle
var _sun: DirectionalLight3D
var _env: Environment
var _tower: GlowTower


## Injected by the Game scene on every peer.
func setup(
		day_night: DayNightCycle,
		sun: DirectionalLight3D,
		world_environment: WorldEnvironment,
		tower: GlowTower) -> void:
	_day_night = day_night
	_sun = sun
	_env = world_environment.environment
	_tower = tower


func _process(_delta: float) -> void:
	if _day_night == null:
		return
	var mix := _night_mix()
	var t := _day_progress()
	var arc := sin(t * PI)

	# The sun's position only means anything by day; through the night it rests
	# where dusk left it (energy is near zero, nobody can tell), then parks at
	# its sunrise spot during pre-dawn so daybreak brightens in place instead
	# of snapping the shadows across the sky.
	if _day_night.phase == DayNightCycle.Phase.DAY:
		var elevation := lerpf(sun_elevation_low, sun_elevation_high, arc)
		_sun.rotation_degrees = Vector3(-elevation, sun_yaw_start + t * sun_yaw_sweep, 0.0)
	elif _day_night.time_remaining() < _day_night.transition_time:
		_sun.rotation_degrees = Vector3(-sun_elevation_low, sun_yaw_start, 0.0)
	_sun.light_energy = lerpf(lerpf(sun_energy_low, sun_energy_high, arc),
			sun_energy_night, mix)
	_sun.light_color = sun_color_noon.lerp(sun_color_horizon, 1.0 - arc)

	_env.background_color = sky_horizon.lerp(sky_day, arc).lerp(sky_night, mix)
	_env.ambient_light_color = ambient_day.lerp(ambient_night, mix)
	_env.ambient_light_energy = lerpf(
			lerpf(ambient_energy_low, ambient_energy_high, arc),
			ambient_energy_night, mix)

	var pulse := sin(_day_night.time_in_phase * TAU / tower_pulse_period) \
			* tower_pulse_energy * mix
	_tower.set_light_energy(lerpf(tower_energy_day, tower_energy_night, mix) + pulse)
	# The daylight bubble contracts into the night pool as dusk falls.
	_tower.set_light_range(lerpf(tower_range_day, tower_range_night, mix))
	# Shadows only in FULL night: broken on the Compatibility fallback and on
	# Metal (gated inside set_light_shadows), and a shadowed omni over-darkens
	# its range box in daylight on some Vulkan drivers — so never while the
	# bubble is expanded, not even partway through dawn/dusk (decision log).
	_tower.set_light_shadows(mix > 0.995)

	# Billboards: gloom outside the light's reach, the time-of-day look inside,
	# warmed toward the glow deep in the pool — the billboard twin of what the
	# real light does to the meshes.
	var base_tint := tint_noon.lerp(tint_horizon, 1.0 - arc).lerp(tint_night, mix)
	var glow_strength := lerpf(glow_strength_day, glow_strength_night, mix)
	for group in [&"players", &"enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			var reach: float = clampf(
					1.0 - node.global_position.length() / _tower.light_range(),
					0.0, 1.0)
			var tint := tint_gloom.lerp(base_tint, reach)
			node.set_light_tint(tint.lerp(tint_glow, reach * glow_strength))


# 0.0 (dawn) .. 1.0 (dusk) across the day; frozen at 1.0 all night.
func _day_progress() -> float:
	if _day_night.phase != DayNightCycle.Phase.DAY:
		return 1.0
	var length := _day_night.phase_length()
	if length <= 0.0:
		return 1.0
	return clampf(_day_night.time_in_phase / length, 0.0, 1.0)


# 0.0 in full day .. 1.0 in full night, easing across the boundary over the
# cycle's transition_time — same shape as the 2D ambient_color() fade.
func _night_mix() -> float:
	var fade := clampf(_day_night.time_remaining() / _day_night.transition_time, 0.0, 1.0)
	if _day_night.phase == DayNightCycle.Phase.DAY:
		return 1.0 - fade
	return fade
