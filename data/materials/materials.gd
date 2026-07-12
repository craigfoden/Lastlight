class_name Materials
extends RefCounted
## Registry of every MaterialType, in display order. A "script as namespace"
## (per the best-practices docs) — static access without an autoload.
##
## Recipe: added a new material .tres? Add its preload to ALL.

const ALL: Array[MaterialType] = [
	preload("res://data/materials/wood.tres"),
	preload("res://data/materials/stone.tres"),
	preload("res://data/materials/essence_faint.tres"),
	preload("res://data/materials/essence_bright.tres"),
	preload("res://data/materials/essence_radiant.tres"),
]


static func by_id(id: StringName) -> MaterialType:
	for material in ALL:
		if material.id == id:
			return material
	return null


## "3 Wood, 2 Stone" — for tooltips and the build menu.
static func cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for id in cost:
		var material := by_id(id)
		parts.append("%d %s" % [cost[id], material.display_name if material else String(id)])
	return ", ".join(parts)
