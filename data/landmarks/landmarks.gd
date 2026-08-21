class_name Landmarks
extends RefCounted
## Registry of every LandmarkType, in placement order. A "script as namespace"
## like `Materials`, `Buildings`, `Biomes` and `Camps` — static access without
## an autoload.
##
## Recipe: added a new landmark .tres? Add its preload to ALL. WorldGen reads
## this list directly rather than an exported array on the scene node, so the
## roster is readable from outside game.tscn (session 17's `Buildings` rule) —
## and, in practice, so that adding a landmark touches no scene file at all.
##
## Order matters a little: the most constrained landmarks go first, because
## placement is first-come and a single-biome landmark has far less map to
## choose from than one that may stand anywhere.

const ALL: Array[LandmarkType] = [
	preload("res://data/landmarks/standing_stones.tres"),
	preload("res://data/landmarks/elder_tree.tres"),
	preload("res://data/landmarks/bone_field.tres"),
	preload("res://data/landmarks/the_crag.tres"),
	preload("res://data/landmarks/ruined_spire.tres"),
]


static func by_id(id: StringName) -> LandmarkType:
	for type in ALL:
		if type.id == id:
			return type
	return null
