class_name Regrowth
extends Node
## The world putting itself back, one dawn at a time. Host-only.
##
## Everything harvestable in Lastlight used to be finite: ~380 resource nodes
## and ten camps, each good exactly once. That is fine over three nights and
## wrong over seven — a long run ends with a strip-mined map, a day loop with
## nothing in it, and a party that has to ration a resource the world is still
## visibly covered in. Regrowth is the other end of that: at every dawn a share
## of the felled nodes come back, and a site cleared long enough ago is
## reoccupied.
##
## **Why this is a node of its own** rather than part of WorldGen: WorldGen is a
## pure function of the seed, runs identically on every peer, and syncs nothing
## (see its class doc and GOTCHAS). Regrowth is the opposite of all three — it
## happens on the host, it is deliberately random, and every one of its effects
## travels to clients down an existing RPC lane (`ResourceNode._sync_amount`,
## `Camp._sync_guards`, the enemy spawner). Putting host-authoritative dice
## inside the deterministic generator is exactly the mistake GOTCHAS warns about.
##
## Nothing here is new sync. That is the whole design: regrowth reuses the
## harvest lane, and a repopulated camp reuses the garrison lane.

## Share of the currently-felled resource nodes that come back each dawn. A
## fraction rather than a count so it scales with how hard the map has been
## worked: a lightly-used world barely changes, a stripped one recovers fast
## enough to be worth walking back out into.
@export_range(0.0, 1.0, 0.01) var regrow_share := 0.22

## What a regrown node is worth in chops, as a share of what it was originally.
## Under 1.0 on purpose: second growth is thinner than first growth, so
## returning to a picked-over patch is quicker work per node but the same pay —
## which makes clearing fresh ground still the better use of a day.
@export_range(0.1, 1.0, 0.05) var regrow_stock_share := 0.6

## Dawns before the first regrowth. Nothing comes back on day 1: the first day
## is the one where the map is supposed to feel untouched.
@export var first_regrow_day := 2

var _day_night: DayNightCycle
var _build_manager: BuildManager


## Injected by the Game scene once the world exists, on every peer — the guard
## that keeps this host-only is on the tick, not on the wiring, so a client
## still holds a correctly-wired (and silent) copy.
func setup(day_night: DayNightCycle, build_manager: BuildManager) -> void:
	_day_night = day_night
	_build_manager = build_manager
	day_night.phase_changed.connect(_on_phase_changed)


func _on_phase_changed(phase: DayNightCycle.Phase) -> void:
	if not multiplayer.is_server() or phase != DayNightCycle.Phase.DAY:
		return
	if _day_night.day_number < first_regrow_day:
		return
	var grown := _regrow_resources()
	var reoccupied := _repopulate_camps()
	if grown > 0 or reoccupied > 0:
		print("[Regrowth] Dawn of day %d: %d node(s) regrew, %d camp(s) reoccupied"
				% [_day_night.day_number, grown, reoccupied])


# A share of the felled nodes, chosen at random rather than in tree order — the
# alternative regrows the map from one corner outward, which reads as a bug even
# though the totals are the same.
func _regrow_resources() -> int:
	var felled: Array[ResourceNode] = []
	for node in get_tree().get_nodes_in_group("resource_nodes"):
		var resource := node as ResourceNode
		# Loot caches are resource nodes too, and they are a camp's business —
		# restocking one here would hand out camp loot with no garrison to get
		# through (see `_repopulate_camps`).
		if resource == null or resource is LootCache or resource.amount > 0:
			continue
		felled.append(resource)
	felled.shuffle()
	var target := int(roundf(felled.size() * regrow_share))
	var grown := 0
	for resource in felled:
		if grown >= target:
			break
		var cell := _build_manager.world_to_cell(resource.global_position)
		# The cell may have been built on, or become the only way to the tower,
		# while it stood empty. A tree that sprouts through a wall — or seals the
		# map — is a worse outcome than a bare patch of ground.
		if not _build_manager.can_grow_at(cell):
			continue
		resource.host_regrow(maxi(int(roundf(resource.starting_amount * regrow_stock_share)), 1))
		grown += 1
	return grown


func _repopulate_camps() -> int:
	var reoccupied := 0
	for node in get_tree().get_nodes_in_group("camps"):
		var camp := node as Camp
		if camp == null or camp.cleared_on_day < 0 or camp.type.repopulate_days <= 0:
			continue
		if _day_night.day_number - camp.cleared_on_day < camp.type.repopulate_days:
			continue
		var cache := camp.get_node_or_null("Cache") as LootCache
		# A site that was cleared but never emptied does not need reoccupying:
		# the reward is still sitting there, and posting a fresh garrison over it
		# would take back a prize the players have already paid for.
		if cache != null and cache.amount > 0:
			continue
		# Same cell test as a resource node's: somebody may have built on the
		# looted cache while the ruin stood empty.
		if cache != null and not _build_manager.can_grow_at(
				_build_manager.world_to_cell(cache.global_position)):
			continue
		camp.host_repopulate()
		reoccupied += 1
	return reoccupied
