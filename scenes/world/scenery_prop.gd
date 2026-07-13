class_name SceneryProp
extends StaticBody2D
## A non-interactive world prop that fills the open map. Solid props block
## movement and join the "obstacles" group so the build grid marks their cell
## unwalkable; decorative props are visual only (collision disabled).
##
## WorldGen builds these from a fixed seed on every peer, so they need no sync.

@export var texture: Texture2D
@export var solid := true

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	if texture != null:
		_sprite.texture = texture
	if solid:
		add_to_group("obstacles")
		# Standing prop: plant it on the shared baseline so Y-sort reads right.
		SpriteAnchor.apply(_sprite)
	else:
		# Decor never blocks anything: drop its collision entirely and draw it
		# as a flat ground decal beneath every standing object.
		z_index = -1
		collision_layer = 0
		_collision.set_deferred("disabled", true)
