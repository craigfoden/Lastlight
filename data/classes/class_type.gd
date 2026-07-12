class_name ClassType
extends Resource
## One playable class. Exclusive towers are NOT listed here — a BuildingType's
## class_id points at us instead, so a building belongs to exactly one place.

## Stable identifier (matches BuildingType.class_id for exclusives).
@export var id: StringName

@export var display_name: String

@export var sprite: Texture2D

@export var move_speed := 150.0

@export var basic_attack: AbilityType
@export var ability_1: AbilityType
@export var ability_2: AbilityType

@export_group("Dodge")
@export var dodge_speed := 430.0
@export var dodge_duration := 0.18
@export var dodge_cooldown := 1.5
