extends Node
## Autoload "Profile": this machine's persistent meta-progression, entirely
## separate from run state. Each player banks their own XP locally — nothing
## here is networked.
##
## Saved to user://profile.cfg (on Windows: %APPDATA%/Godot/app_userdata/Lastlight).

const SAVE_PATH := "user://profile.cfg"

## Simple square-root level curve: level 2 at 100 XP, 3 at 400, 4 at 900...
## Tunable; revisit during balancing.
const XP_PER_LEVEL_STEP := 100.0

var account_xp := 0
var class_xp := {}  # class id (String) -> xp
var unlocked_talents := {}  # class id (String) -> Array of talent id Strings


func _ready() -> void:
	load_profile()


## Called at run end on every peer, each banking its own progress.
func bank_run(class_id: StringName, xp: int) -> void:
	account_xp += xp
	var key := String(class_id)
	class_xp[key] = int(class_xp.get(key, 0)) + xp
	save_profile()
	print("[Profile] Banked %d XP -> account lv %d, %s lv %d"
			% [xp, account_level(), key, class_level(class_id)])


func account_level() -> int:
	return _level_for(account_xp)


func class_level(class_id: StringName) -> int:
	return _level_for(int(class_xp.get(String(class_id), 0)))


## One talent point per class level beyond the first, minus points spent.
func talent_points(class_id: StringName) -> int:
	return class_level(class_id) - 1 - talents_for(class_id).size()


func talents_for(class_id: StringName) -> Array:
	return unlocked_talents.get(String(class_id), [])


func unlock_talent(talent: TalentType) -> bool:
	if talent == null or talent_points(talent.class_id) <= 0:
		return false
	if String(talent.id) in talents_for(talent.class_id):
		return false
	var key := String(talent.class_id)
	var owned: Array = unlocked_talents.get(key, [])
	owned.append(String(talent.id))
	unlocked_talents[key] = owned
	save_profile()
	print("[Profile] Unlocked talent %s" % talent.id)
	return true


## Combined stat modifiers from every unlocked talent of a class.
func modifiers_for(class_id: StringName) -> Dictionary:
	var combined := {}
	for talent_id in talents_for(class_id):
		var talent := Talents.by_id(StringName(talent_id))
		if talent == null:
			continue
		for key in talent.modifiers:
			# Multiplicative keys multiply; anything else overwrites.
			if String(key).ends_with("_mult"):
				combined[key] = float(combined.get(key, 1.0)) * talent.modifiers[key]
			else:
				combined[key] = talent.modifiers[key]
	return combined


func save_profile() -> void:
	var config := ConfigFile.new()
	config.set_value("profile", "account_xp", account_xp)
	config.set_value("profile", "class_xp", class_xp)
	config.set_value("profile", "unlocked_talents", unlocked_talents)
	config.save(SAVE_PATH)


func load_profile() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return  # first launch: defaults stand
	account_xp = config.get_value("profile", "account_xp", 0)
	class_xp = config.get_value("profile", "class_xp", {})
	unlocked_talents = config.get_value("profile", "unlocked_talents", {})
	print("[Profile] Loaded: account lv %d (%d XP)" % [account_level(), account_xp])


func _level_for(xp: int) -> int:
	return 1 + int(sqrt(xp / XP_PER_LEVEL_STEP))
