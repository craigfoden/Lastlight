class_name CampType
extends Resource
## One kind of guarded site out in the wilds — a bandit camp, a ruined hamlet,
## a barrow. Data-driven: adding a camp = a .tres file + adding it to
## `camp_types` on World/WorldGen, no new code (see the recipe in CLAUDE.md).
##
## A camp is three things authored together: a **footprint** of ruined walls
## stamped into the world, a **garrison** of leashed guards standing in it, and
## a **cache** at its heart that stays locked until the last guard falls. The
## distance band is what ties risk to reward — outer camps hold the essences the
## ambient scatter no longer gives up (see GAME_DESIGN.md).

## Stable identifier used in log lines and (later) save data.
@export var id: StringName

@export var display_name: String

## One or two sentences of flavour — shown on the cache's interact prompt.
@export_multiline var description := ""

@export_group("Placement")
## How many of this camp WorldGen scatters. The whole roster is placed from the
## same deterministic seed, so this is a world-shape dial, not a chance.
@export var site_count := 3
## Ring band this camp is scattered in, in cells (WorldGen's `world_extent` is
## the outer bound of the map). Risk and reward both key off distance.
@export var radius_min := 20.0
@export var radius_max := 50.0
## Half-extent of the ruined wall footprint, in cells: a `footprint_radius` of 3
## stamps a 7x7 site. The perimeter is walls, the interior is left open.
@export var footprint_radius := 3
## Cells kept clear around the cache at the centre, so the loot is never walled
## in by its own perimeter and guards have room to stand.
@export var courtyard_radius := 1

@export_group("Garrison")
## What stands guard here. Must also appear in `guard_types` on the
## WaveDirector node — that is the array spawn packets resolve ids out of.
@export var guard_type: EnemyType
@export var guard_count := 3
## How far from the centre guards are posted, in cells. Kept inside the
## footprint so a camp reads as garrisoned rather than as a picket line.
@export var guard_post_radius := 1.6
## How far a guard will chase before giving up and walking home, in cells.
## This is what stops a camp from bleeding its garrison across the map: pull
## one guard and the rest stay put, but you can never kite the whole site away.
@export var guard_leash := 12.0

@export_group("Reward")
## material id -> amount, paid into the shared pool in one lump when the cache
## is looted. Authored gross: there is no per-player scaling, the same as every
## other material payout in the game.
@export var loot: Dictionary
