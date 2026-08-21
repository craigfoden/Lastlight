class_name LandmarkType
extends Resource
## One large, unmistakable feature of the wilds — a ring of standing stones, a
## crag, the elder tree. Data-driven: adding a landmark = a .tres file + a
## preload in the `Landmarks` registry, no new code (see the recipe in
## CLAUDE.md).
##
## **A landmark does nothing, on purpose.** It grants no boon, holds no loot and
## spawns no guard — everything a player can *do* out in the wilds is a camp
## (session 15) or a resource node, and adding a third answer would have been a
## new unplayed number on top of eight sessions of them. What a landmark is for
## is the one thing biomes could not buy on their own: before this, one stretch
## of thicket looked exactly like the next, so the wilds were navigable by
## minimap and by nothing else. A landmark is a fixed point you can see, name,
## and steer by.
##
## It follows CampType's shape deliberately — a site count, a distance band, a
## footprint stamped by WorldGen from the run seed — with two differences that
## are the whole design:
##  * **Biome affinity** (`biome_ids`). A landmark belongs to a country. Standing
##    stones stand in a leyfield; the elder tree grows in a thicket. So the
##    landmark you can see tells you what grows around it before you have walked
##    close enough to count the trees — which is what makes it navigation rather
##    than decoration. A run that rolls no leyfield gets no standing stones, and
##    that is the feature working: it is what makes one map memorable against
##    another.
##  * **The clearing is part of the landmark.** WorldGen reserves the whole
##    footprint against the resource and solid-prop scatter, so the feature
##    stands in its own open ground. Without that, a thicket at 1.3 density
##    simply buries the elder tree in ordinary trees.
##
## Landmarks carry no state whatsoever, so — unlike camps, whose garrisons are
## host-simulated — nothing here is ever networked. Every peer generates the
## same landmarks from the same seed, the same contract the scatter has always
## had (see GOTCHAS on WorldGen determinism).

## How the pieces are laid out around the site's centre.
##  * RING places them evenly around the footprint's edge, leaving the middle
##    open — a place you walk into.
##  * CLUSTER scatters them inside the footprint around an optional centrepiece.
## Append only — `arrangement` is stored as an int in the .tres files. A third
## shape worth having later is a ridge or line, which is the one that would give
## *directional* bearing rather than a point to steer at.
enum Arrangement { RING, CLUSTER }

## Stable identifier used in log lines and the layout hash.
@export var id: StringName

## Shown by the HUD's place banner when you are standing at this landmark.
@export var display_name: String

## One or two sentences of flavour. Not yet shown anywhere — the banner has
## room for a name and no more — but authored with the rest so a later screen
## has something to say.
@export_multiline var description := ""

@export_group("Placement")
## How many of this landmark WorldGen tries to place. Deliberately small: a
## landmark you meet three times in one run is scenery, not a landmark.
@export var site_count := 1
## Ring band this landmark is scattered in, in cells. Most sit outside the safe
## radius — home already has the tower, which is the landmark that matters.
@export var radius_min := 24.0
@export var radius_max := 88.0
## Half-extent of the site, in cells: a `footprint_radius` of 4 reserves a 9x9
## clearing. RING lays its pieces on the edge of that; CLUSTER fills it.
@export var footprint_radius := 4
## Which countries this landmark belongs to, by `BiomeType.id`. Empty means
## anywhere in the wilds — use it sparingly, since a landmark that can turn up
## in any country tells you nothing about the one you are in.
@export var biome_ids: Array[StringName] = []

@export_group("Pieces")
## How the pieces sit on the ground. See `Arrangement`.
@export var arrangement := Arrangement.RING
## The one big mesh at the middle of the site (the trunk, the spire, the skull).
## Optional: a ring of stones is all edge and no centre.
@export var centerpiece_scene: PackedScene
## The repeated pieces — monoliths, boulders, ribs. Picked per cell.
@export var piece_scenes: Array[PackedScene] = []
## How many of those to lay out. A RING spaces this many evenly around the
## edge; a CLUSTER drops this many inside the footprint.
@export var piece_count := 8
## How far a RING piece may slide off its even share of the circle, as a
## fraction of the gap between neighbours, and how far in or out it may sit.
## Zero on both would give a ring drawn with a compass, which reads as authored.
@export var ring_angle_jitter := 0.25
@export var ring_radius_jitter := 0.8

@export_group("Reading it")
## How near you must stand, in cells, before the HUD's place banner names this
## landmark. Generous by default: the point of the banner is to confirm what you
## are already looking at, and you can see one of these long before you reach it.
@export var sight_radius := 14.0
## Dot colour on the minimap. Landmarks are drawn as a small diamond so they
## cannot be mistaken for a resource dot or a camp ring.
@export var map_color := Color(0.85, 0.82, 0.7)
