class_name Building
extends StaticBody2D
## A placed structure (wall or tower). Every peer builds an identical node
## from replicated spawn data; only the host runs targeting and applies
## damage. Shot visuals are cosmetic and drawn locally on each peer.

const ShotTexture := preload("res://assets/sprites/placeholder/arrow_shot.svg")

## Pixels per second for the cosmetic projectile sprite.
const SHOT_SPEED := 500.0

var type: BuildingType
var cell: Vector2i

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _fire_timer: Timer = $FireTimer


## Called by the spawn function before entering the tree.
func setup(new_type: BuildingType, new_cell: Vector2i) -> void:
	type = new_type
	cell = new_cell


func _ready() -> void:
	print("[Building] %s at %s" % [type.id, cell])
	_sprite.texture = type.texture
	if type.attacks and multiplayer.is_server():
		_fire_timer.wait_time = type.fire_interval
		_fire_timer.timeout.connect(_host_fire)
		_fire_timer.start()


# Host only: pick a target, apply damage, tell everyone to draw the shot.
func _host_fire() -> void:
	var target := _nearest_living_enemy()
	if target == null:
		return
	target.host_take_damage(type.damage)
	_show_shot.rpc(target.global_position)


func _nearest_living_enemy() -> Node2D:
	var best: Node2D = null
	var best_dist := type.attack_range * type.attack_range
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.hp <= 0:
			continue
		var dist: float = global_position.distance_squared_to(enemy.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = enemy
	return best


# Cosmetic only — the host already applied the damage.
@rpc("authority", "call_local", "unreliable")
func _show_shot(target_pos: Vector2) -> void:
	var shot := Sprite2D.new()
	shot.texture = ShotTexture
	shot.top_level = true
	shot.global_position = global_position
	shot.rotation = global_position.angle_to_point(target_pos)
	add_child(shot)
	var tween := shot.create_tween()
	var flight_time := global_position.distance_to(target_pos) / SHOT_SPEED
	tween.tween_property(shot, "global_position", target_pos, flight_time)
	tween.tween_callback(shot.queue_free)
