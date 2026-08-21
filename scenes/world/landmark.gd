class_name Landmark
extends Node3D
## A named feature of the wilds — a marker node standing at the middle of the
## pieces WorldGen stamped around it.
##
## This node holds no state and does nothing per frame. It exists so that the
## two things which need to *find* a landmark can do so through a group instead
## of reaching into the generator: the minimap draws one diamond per member of
## `"landmarks"`, and the HUD's place banner asks the nearest one for its name.
## That is the same split camps use (WorldGen owns the layout, the node owns the
## identity) minus the half camps needed a host for — a landmark has no
## garrison, no lock and no reward, so nothing here is ever networked.
##
## The pieces are children rather than siblings, so a landmark is one subtree
## that can be reasoned about (and, later, cleared) as one thing. Their names are
## seed-deterministic like everything else WorldGen builds, though nothing here
## resolves an RPC by path — see GOTCHAS on why that rule exists at all.

## What this landmark is. Never null once configure() has run.
var type: LandmarkType


## Called by WorldGen before add_child, on every peer.
func configure(landmark_type: LandmarkType) -> void:
	type = landmark_type


func _ready() -> void:
	add_to_group("landmarks")


## How near the given ground-plane point is to being "at" this landmark, as a
## fraction of its sight radius (0 at the centre, 1 at the edge, above 1 outside).
## Returned as a ratio rather than a distance so the HUD can pick between a
## sprawling bone field and a compact spire without knowing either one's size.
func sight_ratio(point: Vector3) -> float:
	if type == null or type.sight_radius <= 0.0:
		return INF
	var offset := Vector2(point.x - global_position.x, point.z - global_position.z)
	return offset.length() / type.sight_radius
