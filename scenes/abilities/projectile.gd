class_name Projectile
extends Area2D
## A player shot. Spawned on every peer by the same broadcast with identical
## parameters, so each peer animates it locally — but only the host's copy
## deals damage (its enemies are the authoritative ones).

const SpriteTexture := preload("res://assets/sprites/placeholder/arrow_shot.svg")

var _ability: AbilityType
var _direction := Vector2.RIGHT
var _travelled := 0.0
var _hits_left := 0


func setup(ability: AbilityType, from: Vector2, direction: Vector2) -> void:
	_ability = ability
	_direction = direction
	_hits_left = 1 + ability.pierce
	position = from
	rotation = direction.angle()


func _ready() -> void:
	$Sprite2D.texture = SpriteTexture
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	var step := _ability.projectile_speed * delta
	position += _direction * step
	_travelled += step
	if _travelled >= _ability.projectile_range:
		queue_free()


# Host only: clients' copies are visual and just fly their full range.
func _on_body_entered(body: Node2D) -> void:
	if _hits_left <= 0 or not body.is_in_group("enemies") or body.hp <= 0:
		return
	body.host_take_damage(_ability.damage)
	_hits_left -= 1
	if _hits_left <= 0:
		queue_free()
