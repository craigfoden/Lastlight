class_name EnemyType
extends Resource
## One monster kind. Data-driven: adding an enemy = a .tres file + a sprite,
## no new code (see the recipe in CLAUDE.md).

## Stable identifier used in spawn RPCs and (later) save data.
@export var id: StringName

@export var display_name: String

@export var texture: Texture2D

@export var max_hp := 10

## Pixels per second.
@export var move_speed := 60.0

@export_group("Attack")
@export var damage := 3
## Seconds between swings (at the tower, or at a player when roaming).
@export var attack_interval := 1.5
## Pixels from the target at which it stops and starts swinging.
@export var attack_range := 48.0
## Roaming only: how close a player must come before this monster gives chase.
@export var aggro_range := 260.0
