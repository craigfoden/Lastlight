class_name AbilityType
extends Resource
## One castable ability (a class's basic attack is also one of these).
## Data-driven: adding an ability = a .tres file; behavior comes from `kind`.

## PROJECTILE flies and hits; DEPLOYABLE sits on the ground and waits;
## MELEE_ARC is an instant swing in a wedge around the caster; SELF_BUFF
## changes the caster for a while and touches no one else.
## Append only — `kind` is stored as an int in the .tres files.
enum Kind { PROJECTILE, DEPLOYABLE, MELEE_ARC, SELF_BUFF }

## Stable identifier used in cast RPCs and (later) save data.
@export var id: StringName

@export var display_name: String

## One or two sentences for the ability-bar tooltip — what it does and when
## to use it. Stats are appended automatically; don't repeat numbers here.
@export_multiline var description := ""

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

@export_group("Melee arc")
## Pixels from the caster the swing reaches (see `damage` above for its bite).
@export var melee_range := 48.0
## Width of the wedge the swing covers, centred on the aim direction. 360 is a
## full circle around the caster — the difference between a cleave and a slam
## is this number and nothing else.
@export_range(0.0, 360.0, 1.0) var arc_degrees := 100.0
## How long the swing stays visible. Damage lands on the first host tick;
## this is purely how long the wedge is drawn.
@export var swing_time := 0.2

@export_group("Self buff")
@export var buff_duration := 4.0
## Share of incoming damage shrugged off while the buff is up (0.4 = 40% less).
@export_range(0.0, 1.0, 0.05) var damage_reduction := 0.0
