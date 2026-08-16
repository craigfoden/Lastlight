class_name Camps
extends RefCounted
## Registry of every CampType, in placement order (nearest band first). A
## "script as namespace" like `Materials` and `Buildings` — static access
## without an autoload.
##
## Recipe: added a new camp .tres? Add its preload to ALL. WorldGen reads this
## list directly rather than an exported array on the scene node, so a camp
## roster is readable from outside game.tscn (session 17's `Buildings` rule).

const ALL: Array[CampType] = [
	preload("res://data/camps/bandit_camp.tres"),
	preload("res://data/camps/ruined_hamlet.tres"),
	preload("res://data/camps/warband_barrow.tres"),
]


static func by_id(id: StringName) -> CampType:
	for type in ALL:
		if type.id == id:
			return type
	return null
