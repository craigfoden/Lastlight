class_name BiomeType
extends Resource
## One kind of country out in the wilds — a thicket, a barrens, an ashfield.
## Biomes are what make two runs on two seeds different *places* rather than
## the same place with the props shuffled: before them the whole map beyond the
## safe zone was one uniform scatter with rarity keyed on distance alone.
##
## A biome is a **region**, not a per-cell roll. WorldGen drops a handful of
## biome sites in the wilds and every cell belongs to the nearest one (a Voronoi
## partition), so a biome is a contiguous stretch of country you can walk into
## and notice. What it changes is deliberately narrow:
##  * which materials the resource scatter favours there (`material_weights`),
##  * how thickly that region is scattered at all (the three densities),
##  * what colour the ground reads as (`ground_color`, blended by ground.gdshader
##    from the same site list, so what you see and what you harvest agree).
##
## What it deliberately does NOT change is the distance-based rarity bands. A
## leyfield near the village does not hand out Radiant Essence: `material_weights`
## reweights *within* the band the distance already chose, and Radiant is exempt
## from biome weighting entirely (see WorldGen `_material_for`), because that 4 %
## is the dial the whole camp economy is balanced against (session 15).

## Stable identifier, used in logs and the layout hash.
@export var id: StringName

@export var display_name: String

## One or two sentences of flavour, for the run-start log and (later) any UI
## that names where you are.
@export_multiline var description := ""

## How often this biome is drawn when sites are assigned, relative to the other
## biomes in `Biomes.ALL`. A world-shape dial: raise it and more of the map is
## this country.
@export var weight := 1.0

@export_group("Look")
## Multiplied over the wilds ground tile inside this biome. Kept as a tint
## rather than a tile of its own so a biome costs no new art and the ground
## stays one repeating pixel tile — the thing that made the floor read as pixel
## art in the first place (session 17).
@export var ground_color := Color(1, 1, 1)

@export_group("Scatter")
## Per-material multiplier on the odds the distance band already chose:
## material id -> weight. Anything not listed keeps its band weight (1.0).
## `essence_radiant` is ignored here on purpose — see the class doc.
@export var material_weights: Dictionary

## Share of this biome's resource rolls that are kept. 1.0 is the map-wide
## density; 0.6 is a thin, picked-over country and 1.4 a rich one. Rolls that
## are dropped are *not* re-rolled elsewhere, so a map full of sparse biomes is
## genuinely a poorer map.
@export var resource_density := 1.0

## The same, for solid cover (rocks, stumps — the things that block movement and
## bend a night lane) and for flat decor.
@export var solid_density := 1.0
@export var decor_density := 1.0
