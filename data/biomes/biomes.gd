class_name Biomes
extends RefCounted
## Registry of every BiomeType. A "script as namespace" like `Materials` and
## `Buildings` — static access without an autoload.
##
## Recipe: added a new biome .tres? Add its preload to ALL. WorldGen draws every
## biome site from this list weighted by `BiomeType.weight`, so a new entry
## starts appearing in worlds immediately, with no other change.

const ALL: Array[BiomeType] = [
	preload("res://data/biomes/thicket.tres"),
	preload("res://data/biomes/barrens.tres"),
	preload("res://data/biomes/ashfield.tres"),
	preload("res://data/biomes/leyfield.tres"),
]


static func by_id(id: StringName) -> BiomeType:
	for biome in ALL:
		if biome.id == id:
			return biome
	return null
