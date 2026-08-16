class_name Talents
extends RefCounted
## Registry of every TalentType ("script as namespace", like Materials).
## Recipe: new talent .tres? Add its preload to ALL.

## Three per class, deliberately the same three shapes: a movement talent, a
## cooldown talent, and a dodge talent. They all scale numbers the owning peer
## already simulates alone (see the talent hooks in player.gd) — the first
## talent that wants a host-authoritative stat is the one that has to answer how
## meta-progression reaches the host, and none of these do.
const ALL: Array[TalentType] = [
	preload("res://data/talents/ranger_fleetfoot.tres"),
	preload("res://data/talents/ranger_quick_nock.tres"),
	preload("res://data/talents/ranger_light_step.tres"),
	preload("res://data/talents/paladin_long_march.tres"),
	preload("res://data/talents/paladin_vigil.tres"),
	preload("res://data/talents/paladin_sure_footing.tres"),
	preload("res://data/talents/mage_hastened.tres"),
	preload("res://data/talents/mage_ley_attunement.tres"),
	preload("res://data/talents/mage_blink_step.tres"),
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
