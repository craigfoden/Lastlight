class_name Projectile
extends Area3D
## A player shot in the 3D world. Spawned on every peer by the same broadcast
## with identical parameters, so each peer animates it locally — but only the
## host's copy deals damage (its enemies are the authoritative ones). Same
## contract as the 2D Projectile; flight is on the XZ plane at chest height.

## 2D ability data is px-denominated; convert at the boundary (32 px = 1 unit).
const PX_PER_UNIT := 32.0
## Height above the ground plane the shot flies at (enemy capsule center).
const FLIGHT_HEIGHT := 0.5

var _ability: AbilityType
var _direction := Vector3.RIGHT
var _travelled := 0.0
var _hits_left := 0


## `from` is the caster's ground position — the flight height is applied here,
## identically on every peer.
func setup(ability: AbilityType, from: Vector3, direction: Vector3) -> void:
	_ability = ability
	_direction = Vector3(direction.x, 0.0, direction.z).normalized()
	_hits_left = 1 + ability.pierce
	position = from + Vector3(0, FLIGHT_HEIGHT, 0)
	# Aim the arrow mesh along the flight direction (-Z is a Node3D's forward).
	basis = Basis.looking_at(_direction)


func _ready() -> void:
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	var step := (_ability.projectile_speed / PX_PER_UNIT) * delta
	position += _direction * step
	_travelled += step
	if _travelled >= _ability.projectile_range / PX_PER_UNIT:
		queue_free()


# Host only: clients' copies are visual and just fly their full range.
func _on_body_entered(body: Node3D) -> void:
	if _hits_left <= 0 or not body.is_in_group("enemies") or body.hp <= 0:
		return
	body.host_take_damage(_ability.damage)
	_hits_left -= 1
	if _hits_left <= 0:
		queue_free()
