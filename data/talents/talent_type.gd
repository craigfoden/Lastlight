class_name TalentType
extends Resource
## One node on a class's talent tree. Effects are data: a dictionary of
## stat-modifier keys the player applies on spawn. Costs 1 talent point.

@export var id: StringName

## Which class's tree this belongs to (matches ClassType.id).
@export var class_id: StringName

@export var display_name: String

@export_multiline var description: String

## Stat modifiers, e.g. { &"move_speed_mult": 1.1 }. Keys are defined by
## whoever consumes them (player.gd today); add new keys as talents need them.
@export var modifiers: Dictionary
