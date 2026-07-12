class_name Enemy
extends CharacterBody2D
## One monster. Host-simulated: the host runs pathfinding, movement, and
## attacks; clients receive position from the synchronizer and hp via RPC.
## Honors the group-"enemies" contract towers target:
## hp + host_take_damage() + host_send_snapshot().

var type: EnemyType
var hp := 0:
	set(value):
		hp = value
		_update_appearance()

var _build_manager: BuildManager
var _tower: GlowTower
var _path := PackedVector2Array()
var _path_index := 0
var _attack_cooldown := 0.0
var _root_remaining := 0.0

@onready var _sprite: Sprite2D = $Sprite2D


## Called by the spawn function on every peer. The node refs are each peer's
## own local instances; only the host actually uses them.
func setup(
		new_type: EnemyType,
		start_position: Vector2,
		build_manager: BuildManager,
		tower: GlowTower) -> void:
	type = new_type
	position = start_position
	_build_manager = build_manager
	_tower = tower


func _ready() -> void:
	_sprite.texture = type.texture
	hp = type.max_hp
	if not multiplayer.is_server():
		set_physics_process(false)
		return
	# Mazes change under our feet; recompute whenever the grid does.
	_build_manager.grid_changed.connect(_repath)
	_repath()


func _physics_process(delta: float) -> void:
	if hp <= 0 or _tower.hp <= 0:
		return
	if global_position.distance_to(_tower.global_position) <= type.attack_range:
		velocity = Vector2.ZERO
		_attack_cooldown -= delta
		if _attack_cooldown <= 0.0:
			_attack_cooldown = type.attack_interval
			_tower.host_take_damage(type.damage)
		return
	if _root_remaining > 0.0:
		# Rooted: no walking (attacking, above, still works).
		_root_remaining -= delta
		velocity = Vector2.ZERO
		return
	if _path_index >= _path.size():
		_repath()
		if _path.is_empty():
			return
	var waypoint := _path[_path_index]
	if global_position.distance_to(waypoint) < 6.0:
		_path_index += 1
		return
	velocity = global_position.direction_to(waypoint) * type.move_speed
	move_and_slide()


## Host only: snare traps (and future crowd control) pin the enemy in place.
func host_apply_root(duration: float) -> void:
	if multiplayer.is_server():
		_root_remaining = maxf(_root_remaining, duration)


## Host only (towers and player shots call this).
func host_take_damage(amount: int) -> void:
	if not multiplayer.is_server() or hp <= 0:
		return
	var new_hp := maxi(hp - amount, 0)
	_sync_hp.rpc(new_hp)
	if new_hp == 0:
		print("[Enemy] %s (%s) died" % [name, type.id])
		# Freeing on the host despawns it on every peer via the spawner.
		queue_free()


## Host only: bring a late joiner up to date.
func host_send_snapshot(peer_id: int) -> void:
	_sync_hp.rpc_id(peer_id, hp)


func _repath() -> void:
	_path = _build_manager.path_to_heart(global_position)
	_path_index = 0


@rpc("authority", "call_local", "reliable")
func _sync_hp(new_hp: int) -> void:
	hp = new_hp


func _update_appearance() -> void:
	if _sprite == null:
		return
	_sprite.modulate.a = lerpf(0.4, 1.0, float(hp) / float(maxi(type.max_hp, 1)))
