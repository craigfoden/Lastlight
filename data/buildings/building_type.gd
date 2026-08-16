class_name BuildingType
extends Resource
## One placeable structure (wall, tower...). Data-driven: adding a building
## = a .tres file + a sprite, no new code (see the recipe in CLAUDE.md).

## Stable identifier used in placement RPCs and (later) save data.
@export var id: StringName

@export var display_name: String

## One or two sentences for the hotbar tooltip — what it does and why you'd
## pick it. Stats are appended automatically; don't repeat numbers here.
@export_multiline var description := ""

## material id -> amount.
@export var cost: Dictionary

## Fraction of `cost` returned when this building is removed. Walls refund in
## full (1.0); towers salvage for less (0.5). Data-driven so every building
## tunes its own value — no magic numbers in the removal logic.
@export_range(0.0, 1.0, 0.05) var refund_fraction := 1.0

## The tier this building becomes when upgraded in place, or null when it is the
## last tier. Upgrading reuses the wall->tower replacement path: you hold the
## base tower's hammer and click the one already standing (the resolution rule
## lives in BuildManager.resolve_placement).
@export var upgrades_to: BuildingType

## False for upgrade tiers. They still live in `buildable_types` so placement
## RPCs can resolve their ids, but they are never their own hotbar slot — you
## reach a tier by upgrading into it, never by placing it from scratch.
@export var placeable := true

## The 3D port's look for this building — a small mesh scene instantiated by
## Building (the 2D game ignores this field). Placeholder meshes live in
## scenes/building/visuals/.
@export var visual_3d: PackedScene

## Empty = shared with every class. Enforced when classes land (session 4);
## until then everything is placeable by everyone.
@export var class_id: StringName = &""

## How much punishment this structure takes before it falls. Enemies only ever
## turn on buildings when the way round is much longer than the way through
## (Enemy `breach_ratio`), so this is the number that decides how long a maze
## buys you once the horde has decided to chew it rather than walk it — not how
## long a wall survives being attacked from the first night, which is not a
## thing that happens.
@export var max_hp := 60

@export_group("Attack")
@export var attacks := false
@export var damage := 0
## Pixels. Towers target the nearest live enemy inside this radius.
@export var attack_range := 0.0
## Seconds between shots.
@export var fire_interval := 1.0


## This tier and every one above it, base first — the whole upgrade line. The
## `has()` guard makes a mis-authored cycle in the .tres files terminate with a
## short chain instead of hanging the game.
func upgrade_chain() -> Array[BuildingType]:
	var chain: Array[BuildingType] = []
	var tier: BuildingType = self
	while tier != null and not chain.has(tier):
		chain.append(tier)
		tier = tier.upgrades_to
	return chain


## What selling this returns: each cost line scaled by `refund_fraction` and
## floored (no free rounding-up of an odd cost); zero lines drop out. The one
## place the refund rule lives — the sell RPC and the sell-mode hint both ask
## here, so what the UI promises is what the host pays.
func refund() -> Dictionary:
	var result := {}
	for material_id in cost:
		var amount := int(floor(cost[material_id] * refund_fraction))
		if amount > 0:
			result[material_id] = amount
	return result
