class_name SpriteAnchor
extends RefCounted
## The 3/4-view baseline convention: every STANDING world object plants the
## bottom of its sprite 16 px below its node origin — the bottom edge of the
## 32 px cell it occupies. Y-sort compares node origins, so a shared baseline
## is what makes "south of a thing = in front of it" read correctly for
## sprites of any height (32 px rocks, 48 px trees, 40 px walls alike).
## Flat decals (decor scenery, traps) skip this: they stay cell-centred and
## draw at z_index -1, under everything that stands.

## Distance from a node's origin down to its visual baseline, in pixels.
const BASELINE := 16.0


## Anchors the sprite's bottom edge on the baseline via its texture-space
## offset. Call after assigning `texture`; the sprite's position stays (0, 0).
static func apply(sprite: Sprite2D) -> void:
	if sprite.texture == null:
		return
	sprite.offset = Vector2(0.0, BASELINE - sprite.texture.get_height() / 2.0)
