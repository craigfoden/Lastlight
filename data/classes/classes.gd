class_name Classes
extends RefCounted
## Registry of every ClassType ("script as namespace", like Materials and
## Talents). Recipe: new class .tres? Add its preload to ALL and it shows up on
## the class-select screen, in spawn data, and in the build hotbar's gating.
##
## Order matters in one place only: ALL[0] is the fallback for an unknown id.

const ALL: Array[ClassType] = [
	preload("res://data/classes/ranger.tres"),
	preload("res://data/classes/paladin.tres"),
	preload("res://data/classes/mage.tres"),
]


## Never returns null. A class id arrives from a peer's roster entry or a
## `--class=` argument, and Player dereferences the result unguarded in _ready —
## an unknown id should drop you back to the default class, not crash the game.
static func by_id(id: StringName) -> ClassType:
	for class_type in ALL:
		if class_type.id == id:
			return class_type
	push_warning("Unknown class id '%s' — falling back to '%s'." % [id, ALL[0].id])
	return ALL[0]


static func has_id(id: StringName) -> bool:
	for class_type in ALL:
		if class_type.id == id:
			return true
	return false
