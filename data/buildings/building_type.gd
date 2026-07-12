class_name BuildingType
extends Resource
## One placeable structure (wall, tower...). Data-driven: adding a building
## = a .tres file + a sprite, no new code (see the recipe in CLAUDE.md).

## Stable identifier used in placement RPCs and (later) save data.
@export var id: StringName

@export var display_name: String

## material id -> amount. Selling refunds this in full (session-2 decision).
@export var cost: Dictionary

@export var texture: Texture2D

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
