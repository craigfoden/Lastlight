class_name WaveDirector
extends Node
## Night-wave scheduler. Host-only logic: when night falls it queues up an
## escalating number of monsters, spawns them through the map's openings on a
## timer, and burns whatever survives at dawn. Enemies replicate through the
## MultiplayerSpawner below; clients only ever see the results.

## Fired on the host at dawn when the tower survived the night.
signal night_survived(night_number: int)

const EnemyScene := preload("res://scenes/enemy/enemy.tscn")

## Monster roster for this run, in escalation order (index 0 = the baseline).
## Recipe: new enemy .tres goes in this array on the WaveDirector node.
@export var enemy_types: Array[EnemyType] = []

@export var base_count := 4
@export var count_per_night := 3
## Solo is first-class: waves scale up per *extra* player, not per player.
@export var count_per_extra_player := 2
@export var spawn_interval := 1.5
## Share of fast enemies (index 1) rises each night up to the cap.
@export var fast_share_per_night := 0.1
@export var fast_share_max := 0.4

var _day_night: DayNightCycle
var _build_manager: BuildManager
var _tower: GlowTower
var _spawn_positions: Array[Vector2] = []
var _to_spawn := 0
var _night_number := 0
var _spawn_seq := 0
var _stopped := false

@onready var _spawner: MultiplayerSpawner = $EnemySpawner
@onready var _enemies: Node2D = $Enemies
@onready var _spawn_timer: Timer = $SpawnTimer


func _ready() -> void:
	_spawner.spawn_function = _build_enemy
	_spawn_timer.timeout.connect(_spawn_tick)


## Injected by the Game scene on every peer.
func setup(
		day_night: DayNightCycle,
		build_manager: BuildManager,
		tower: GlowTower,
		spawn_positions: Array[Vector2]) -> void:
	_day_night = day_night
	_build_manager = build_manager
	_tower = tower
	_spawn_positions = spawn_positions
	day_night.phase_changed.connect(_on_phase_changed)


## The run ended: no more waves, clear the field.
func stop() -> void:
	_stopped = true
	_spawn_timer.stop()
	_to_spawn = 0
	if multiplayer.is_server():
		_despawn_all()


func _on_phase_changed(phase: DayNightCycle.Phase) -> void:
	if not multiplayer.is_server() or _stopped:
		return
	if phase == DayNightCycle.Phase.NIGHT:
		_night_number = _day_night.day_number
		_to_spawn = base_count \
				+ count_per_night * (_night_number - 1) \
				+ count_per_extra_player * (Network.player_count() - 1)
		print("[Waves] Night %d: %d monsters incoming" % [_night_number, _to_spawn])
		_spawn_timer.start(spawn_interval)
	else:
		_spawn_timer.stop()
		_to_spawn = 0
		# Dawn: the amplified sunlight burns whatever is still out there.
		_despawn_all()
		if _night_number > 0:
			night_survived.emit(_night_number)


func _spawn_tick() -> void:
	if _to_spawn <= 0:
		_spawn_timer.stop()
		return
	_to_spawn -= 1
	_spawn_seq += 1
	var fast_share := minf(fast_share_per_night * (_night_number - 1), fast_share_max)
	var type := enemy_types[0]
	if enemy_types.size() > 1 and randf() < fast_share:
		type = enemy_types[1]
	var spawn_position := _spawn_positions[_spawn_seq % _spawn_positions.size()]
	spawn_position += Vector2(0, randf_range(-24.0, 24.0))
	_spawner.spawn({"type_id": type.id, "position": spawn_position, "seq": _spawn_seq})


# Runs on every peer; node refs are each peer's own local instances.
func _build_enemy(data: Dictionary) -> Node:
	var enemy := EnemyScene.instantiate()
	enemy.name = "Enemy_%d" % data.seq
	enemy.setup(_type_by_id(data.type_id), data.position, _build_manager, _tower)
	return enemy


func _despawn_all() -> void:
	for enemy in _enemies.get_children():
		enemy.queue_free()


func _type_by_id(type_id: StringName) -> EnemyType:
	for type in enemy_types:
		if type.id == type_id:
			return type
	return null
