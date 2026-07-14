class_name SceneryProp
extends StaticBody3D
## A non-interactive world prop for the 3D map. Solid props show a small mesh
## scene, block movement, and join the "obstacles" group so the build grid
## marks their cell unwalkable (same contract as the 2D SceneryProp); decor
## props are flat ground decals with collision dropped entirely.
##
## WorldGen builds these from a fixed seed on every peer, so they need no sync.

## Solid look — a mesh scene instantiated in _ready.
@export var visual_scene: PackedScene
## Decor look — drawn as a flat one-cell decal lying on the ground.
@export var decal_texture: Texture2D
## Decal quad edge, slightly under one cell so neighbours don't touch.
@export var decal_size := 0.94
## Height the decal floats above the ground plane to avoid z-fighting it.
@export var decal_lift := 0.01
@export var solid := true

@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	if solid:
		add_to_group("obstacles")
		if visual_scene != null:
			add_child(visual_scene.instantiate())
		return
	# Decor never blocks anything: drop its collision entirely and lie flat on
	# the ground — the 3D equivalent of the 2D decal's z_index = -1.
	collision_layer = 0
	_collision.set_deferred("disabled", true)
	var decal := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(decal_size, decal_size)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = decal_texture
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.roughness = 1.0
	mesh.material = mat
	decal.mesh = mesh
	decal.position.y = decal_lift
	add_child(decal)
