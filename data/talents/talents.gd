class_name Talents
extends RefCounted
## Registry of every TalentType ("script as namespace", like Materials).
## Recipe: new talent .tres? Add its preload to ALL.

const ALL: Array[TalentType] = [
	preload("res://data/talents/ranger_fleetfoot.tres"),
]


static func by_id(id: StringName) -> TalentType:
	for talent in ALL:
		if talent.id == id:
			return talent
	return null


static func for_class(class_id: StringName) -> Array[TalentType]:
	var result: Array[TalentType] = []
	for talent in ALL:
		if talent.class_id == class_id:
			result.append(talent)
	return result
