class_name WaveDirector3D
extends Node3D
## Threat scheduler for the 3D world (host-only logic) — the 2D WaveDirector's
## scheduling verbatim; only the spawn geometry became 3D (ring points and
## jitter on the XZ plane, radii in cells). Two jobs:
##  * Night: pour a CONTINUOUS stream of ASSAULT monsters through the map
##    openings until dawn — the spawn rate ramps up as the night wears on and
##    a rising living-cap keeps steady pressure on the tower. Dawn burns any
##    survivors, so nights stay self-contained.
##  * Day: keep a small population of ROAM monsters alive out in the dark
##    (outside the safe zone) so venturing far is never risk-free. They are
##    cleared when night falls and the assault takes over.
## Enemies replicate through the MultiplayerSpawner below; clients only ever
## see the results.

## Fired on the host at dawn when the tower survived the night.
signal night_survived(night_number: int)

const EnemyScene := preload("res://scenes/enemy3d/enemy_3d.tscn")

## Monster roster for this run, in escalation order (index 0 = the baseline).
## Recipe: new enemy .tres goes in this array on the WaveDirector node.
@export var enemy_types: Array[EnemyType] = []

## Night is a CONTINUOUS stream until dawn, not a fixed count. The gap between
## spawns eases from `spawn_interval_start` (dusk trickle) toward
## `spawn_interval_end` (pre-dawn swarm) across the night, then floors at
## `min_spawn_interval`.
@export var spawn_interval_start := 2.5
@export var spawn_interval_end := 0.55
@export var min_spawn_interval := 0.35
## Every night multiplies the interval by this (<1 = faster each night). Solo
## is first-class: extra players raise the living-cap, not this.
@export var interval_scale_per_night := 0.88
## Living ASSAULT monsters are capped so the field stays fair-but-relentless;
## the cap rises per night and per *extra* player. As you thin the horde, more
## pour in up to the cap — pressure never lets up until dawn.
@export var max_alive_base := 10
@export var max_alive_per_night := 4
@export var max_alive_per_extra_player := 4
## Share of fast enemies (index 1) rises each night up to the cap.
@export var fast_share_per_night := 0.1
@export var fast_share_max := 0.5
## Spawn-point jitter along the opening's row, in cells (2D: 24 px).
@export var spawn_jitter := 0.75

@export_group("Daytime threats")
## Roamers kept alive during the day (solo baseline + per extra player).
@export var day_roamer_base := 3
@export var day_roamer_per_player := 1
## How often the day loop tops the roamer population back up.
@export var day_spawn_interval := 3.0
## Roamers spawn on a ring between the safe zone and this radius, in cells
## (2D: 2400 px).
@export var roamer_spawn_max_radius := 75.0

var _day_night: DayNightCycle
var _build_manager: BuildManager3D
var _tower: GlowTower3D
var _spawn_positions: Array[Vector3] = []
var _safe_radius := 0.0
var _night_number := 0
var _spawn_seq := 0
var _stopped := false

@onready var _spawner: MultiplayerSpawner = $EnemySpawner
@onready var _enemies: Node3D = $Enemies
@onready var _spawn_timer: Timer = $SpawnTimer
@onready var _day_timer := Timer.new()


func _ready() -> void:
	_spawner.spawn_function = _build_enemy
	# We reschedule the timer by hand each tick with a fresh (ramping) interval,
	# so it must fire once and wait to be restarted — not auto-repeat.
	_spawn_timer.one_shot = true
	_spawn_timer.timeout.connect(_spawn_tick)
	# Daytime roamer top-up runs on its own cadence; the tick guards on host
	# + day-phase, so it is harmless on clients and at night.
	_day_timer.wait_time = day_spawn_interval
	_day_timer.timeout.connect(_day_tick)
	add_child(_day_timer)
	_day_timer.start()


## Injected by the Game scene on every peer.
func setup(
		day_night: DayNightCycle,
		build_manager: BuildManager3D,
		tower: GlowTower3D,
		spawn_positions: Array[Vector3],
		safe_radius: float) -> void:
	_day_night = day_night
	_build_manager = build_manager
	_tower = tower
	_spawn_positions = spawn_positions
	_safe_radius = safe_radius
	day_night.phase_changed.connect(_on_phase_changed)


## The run ended: no more waves, clear the field.
func stop() -> void:
	_stopped = true
	_spawn_timer.stop()
	if multiplayer.is_server():
		_despawn_all()


func _on_phase_changed(phase: DayNightCycle.Phase) -> void:
	if not multiplayer.is_server() or _stopped:
		return
	if phase == DayNightCycle.Phase.NIGHT:
		# The daytime roamers retreat as the assault masses at the openings.
		_despawn_all()
		_night_number = _day_night.day_number
		print("[Waves] Night %d: the assault begins (continuous until dawn)"
				% _night_number)
		_reschedule_spawn()
	else:
		_spawn_timer.stop()
		# Dawn: the amplified sunlight burns whatever is still out there.
		_despawn_all()
		if _night_number > 0:
			night_survived.emit(_night_number)


# How far through the night we are, 0.0 (dusk) .. 1.0 (dawn). Drives the ramp.
func _night_progress() -> float:
	if _day_night == null:
		return 0.0
	var length := _day_night.phase_length()
	if length <= 0.0:
		return 1.0
	return clampf(_day_night.time_in_phase / length, 0.0, 1.0)


# Restart the spawn timer with the interval for this moment of this night.
func _reschedule_spawn() -> void:
	if not multiplayer.is_server() or _stopped:
		return
	if _day_night == null or _day_night.phase != DayNightCycle.Phase.NIGHT:
		return
	var interval := lerpf(spawn_interval_start, spawn_interval_end, _night_progress())
	interval *= pow(interval_scale_per_night, maxf(_night_number - 1, 0.0))
	_spawn_timer.start(maxf(interval, min_spawn_interval))


func _alive_cap() -> int:
	return max_alive_base \
			+ max_alive_per_night * (_night_number - 1) \
			+ max_alive_per_extra_player * (Network.player_count() - 1)


func _alive_assault() -> int:
	var count := 0
	for enemy in _enemies.get_children():
		if enemy.behavior == Enemy3D.Behavior.ASSAULT and enemy.hp > 0:
			count += 1
	return count


func _spawn_tick() -> void:
	if not multiplayer.is_server() or _stopped:
		return
	if _day_night == null or _day_night.phase != DayNightCycle.Phase.NIGHT:
		_spawn_timer.stop()
		return
	# Keep the field topped up to the (rising) cap, then queue the next spawn.
	if _alive_assault() < _alive_cap():
		_spawn_one_assault()
	_reschedule_spawn()


func _spawn_one_assault() -> void:
	_spawn_seq += 1
	var fast_share := minf(fast_share_per_night * (_night_number - 1), fast_share_max)
	var type := enemy_types[0]
	if enemy_types.size() > 1 and randf() < fast_share:
		type = enemy_types[1]
	var spawn_position := _spawn_positions[_spawn_seq % _spawn_positions.size()]
	spawn_position += Vector3(0, 0, randf_range(-spawn_jitter, spawn_jitter))
	_spawner.spawn({"type_id": type.id, "position": spawn_position, "seq": _spawn_seq})


# Daytime top-up: keep the roamer population at target while it is day.
func _day_tick() -> void:
	if not multiplayer.is_server() or _stopped:
		return
	if _day_night == null or _day_night.phase != DayNightCycle.Phase.DAY:
		return
	if enemy_types.is_empty():
		return
	var target := day_roamer_base + day_roamer_per_player * (Network.player_count() - 1)
	if _alive_roamers() >= target:
		return
	_spawn_seq += 1
	var type := enemy_types[_spawn_seq % enemy_types.size()]
	var radius := randf_range(_safe_radius + 2.5, roamer_spawn_max_radius)
	var spawn_position := Vector3(radius, 0, 0).rotated(Vector3.UP, randf() * TAU)
	_spawner.spawn({
		"type_id": type.id,
		"position": spawn_position,
		"seq": _spawn_seq,
		"roam": true,
	})
	print("[Waves] Day roamer released (%s)" % type.id)


func _alive_roamers() -> int:
	var count := 0
	for enemy in _enemies.get_children():
		if enemy.behavior == Enemy3D.Behavior.ROAM and enemy.hp > 0:
			count += 1
	return count


# Runs on every peer; node refs are each peer's own local instances.
func _build_enemy(data: Dictionary) -> Node:
	var enemy := EnemyScene.instantiate()
	enemy.name = "Enemy_%d" % data.seq
	var behavior: Enemy3D.Behavior = Enemy3D.Behavior.ROAM if data.get("roam", false) \
			else Enemy3D.Behavior.ASSAULT
	enemy.setup(_type_by_id(data.type_id), data.position, _build_manager, _tower,
			behavior, _safe_radius)
	return enemy


func _despawn_all() -> void:
	for enemy in _enemies.get_children():
		enemy.queue_free()


func _type_by_id(type_id: StringName) -> EnemyType:
	for type in enemy_types:
		if type.id == type_id:
			return type
	return null
