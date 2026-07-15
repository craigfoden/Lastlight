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

@export var texture: Texture2D

## The 3D port's look for this building — a small mesh scene instantiated by
## Building (the 2D game ignores this field). Placeholder meshes live in
## scenes/building/visuals/.
@export var visual_3d: PackedScene

## Empty = shared with every class. Enforced when classes land (session 4);
## until then everything is placeable by everyone.
@export var class_id: StringName = &""

@export_group("Attack")
@export var attacks := false
@export var damage := 0
## Pixels. Towers target the nearest live enemy inside this radius.
@export var attack_range := 0.0
## Seconds between shots.
@export var fire_interval := 1.0


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
