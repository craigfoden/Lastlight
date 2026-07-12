class_name AbilityType
extends Resource
## One castable ability (a class's basic attack is also one of these).
## Data-driven: adding an ability = a .tres file; behavior comes from `kind`.

enum Kind { PROJECTILE, DEPLOYABLE }

## Stable identifier used in cast RPCs and (later) save data.
@export var id: StringName

@export var display_name: String

@export var cooldown := 1.0

@export var kind := Kind.PROJECTILE

@export_group("Projectile")
@export var damage := 3
@export var projectile_speed := 420.0
@export var projectile_range := 320.0
## Extra enemies a shot can pass through (0 = stops on first hit;
## a large number makes it a line skill-shot).
@export var pierce := 0

@export_group("Deployable")
## Seconds enemies caught by the deployable cannot move.
@export var root_duration := 2.5
@export var lifetime := 30.0
