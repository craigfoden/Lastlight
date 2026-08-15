class_name LootCache
extends ResourceNode
## The prize at the heart of a camp: one interact, a whole bundle of materials,
## and nothing at all until the garrison is dead.
##
## It is a ResourceNode variant rather than a new interactable because every
## piece of the harvest lane already fits — the same E key, the same host-side
## range check, the same request → validate → broadcast RPCs, the same
## "depleted, so free the cell" derived state, and the same `harvested` signal
## the game scene routes into the shared pool. What a cache changes is only
## the three things ResourceNode leaves open: it *refuses* while guards live,
## it *pays* several materials instead of one, and it says so in its own prompt.
##
## The lock is not this node's state to own. Guard deaths happen on the host, so
## the Camp counts them and pushes the tally here on every peer
## (`set_guards_remaining`) — one synced fact, in one place, instead of two
## nodes trying to agree. Nothing here is a `Camp`-typed reference, which is
## what keeps camp.gd and loot_cache.gd from depending on each other.

## material id -> amount, copied from the CampType by WorldGen. Paid in one
## lump on the single interact that empties the cache.
var loot: Dictionary = {}
## The camp's display name, for the prompt ("Loot the Bandit Camp").
var camp_display_name := "Cache"
## Guards still standing, pushed by the Camp. Above zero, the cache is locked.
var guards_remaining := 0


func _ready() -> void:
	super()
	# The look only exists once the base has instantiated `visual_scene`; the
	# Camp may well have set the tally before that.
	_refresh_lock_visual()


## Called by the Camp on every peer whenever the tally changes (and once at
## spawn). Drives both the gate and the look, so they can never disagree.
func set_guards_remaining(remaining: int) -> void:
	guards_remaining = remaining
	_refresh_lock_visual()


func is_locked() -> bool:
	return guards_remaining > 0


func harvest_block_reason() -> String:
	if is_locked():
		return "%s still standing" % _guard_count_text()
	return ""


func interact_prompt() -> String:
	if is_locked():
		var verb := "stands" if guards_remaining == 1 else "stand"
		return "%s — sealed while %s still %s" % [
				camp_display_name, _guard_count_text(), verb]
	return "E  Loot %s  (%s)" % [camp_display_name, Materials.cost_text(loot)]


func _guard_count_text() -> String:
	return "1 guard" if guards_remaining == 1 else "%d guards" % guards_remaining


# One interact empties it, so this fires exactly once. `harvested` is emitted
# per material — the game scene's router banks one material at a time, and
# reusing it means a camp payout needs no second path into the pool.
func _emit_payout(player: Node3D) -> void:
	for material_id: StringName in loot:
		var material := Materials.by_id(material_id)
		if material == null:
			push_warning("[LootCache] %s lists unknown material %s" % [name, material_id])
			continue
		harvested.emit(material, int(loot[material_id]))
	print("[Loot] %s looted the %s at %v (%s)"
			% [player.name, camp_display_name, global_position, Materials.cost_text(loot)])


# Bars while sealed, a lit prize once the garrison is down — a camp's state has
# to be readable from across the field, not just from the interact prompt. The
# visual is instantiated by ResourceNode._ready, so this is a no-op until then
# and _ready calls it again.
func _refresh_lock_visual() -> void:
	if _visual == null:
		return
	var bars := _visual.get_node_or_null("Bars") as Node3D
	var glow := _visual.get_node_or_null("Glow") as Node3D
	if bars != null:
		bars.visible = is_locked()
	if glow != null:
		glow.visible = not is_locked()
