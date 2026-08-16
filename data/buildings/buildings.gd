class_name Buildings
extends RefCounted
## Registry of every BuildingType ("script as namespace", like Materials,
## Classes and Talents). Recipe: new building .tres? Add its preload to ALL.
##
## This list used to live as an `@export` on the BuildManager node inside
## game.tscn, which made adding a building an edit to the single most
## merge-hostile file in the repo and left the roster unreadable from anywhere
## outside a live game scene — which is why the class-select screen could not
## tell you which tower your class unlocks. Order is hotbar order.
##
## Upgrade tiers belong here too, even though they are never hotbar slots:
## `BuildManager.type_by_id` has to resolve them out of a spawn packet, and
## `placeable = false` is what keeps them off the bar (see building_type.gd).

const ALL: Array[BuildingType] = [
	preload("res://data/buildings/wall.tres"),
	preload("res://data/buildings/sentry_tower.tres"),
	preload("res://data/buildings/arrow_turret.tres"),
	preload("res://data/buildings/hallowed_brazier.tres"),
	preload("res://data/buildings/arcane_spire.tres"),
	preload("res://data/buildings/sentry_tower_ii.tres"),
	preload("res://data/buildings/sentry_tower_iii.tres"),
	preload("res://data/buildings/arrow_turret_ii.tres"),
	preload("res://data/buildings/arrow_turret_iii.tres"),
	preload("res://data/buildings/hallowed_brazier_ii.tres"),
	preload("res://data/buildings/hallowed_brazier_iii.tres"),
	preload("res://data/buildings/arcane_spire_ii.tres"),
	preload("res://data/buildings/arcane_spire_iii.tres"),
]


static func by_id(id: StringName) -> BuildingType:
	for type in ALL:
		if type.id == id:
			return type
	return null


## Everything `class_id` unlocks and nobody else can place — what the
## class-select screen promises you get for picking this class. Tiers are left
## out: they carry their line's `class_id` too, and listing them would read as
## four separate exclusives rather than one tower with a line above it.
static func exclusives_for(class_id: StringName) -> Array[BuildingType]:
	var result: Array[BuildingType] = []
	for type in ALL:
		if type.class_id == class_id and type.placeable:
			result.append(type)
	return result
