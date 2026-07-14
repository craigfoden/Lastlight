class_name SnareTrap
extends Area3D
## A Ranger deployable in the 3D world: roots every enemy on it when
## triggered, then is consumed. Spawned on all peers with a deterministic name
## so the host can broadcast the trigger; only the host detects and applies
## the root. Same contract as the 2D SnareTrap; the look is a flat ground
## decal (the world3d decor idiom), the trigger a squat cylinder over the cell.

var ability: AbilityType

@onready var _lifetime_timer: Timer = $LifetimeTimer


func setup(new_ability: AbilityType, at: Vector3) -> void:
	ability = new_ability
	position = Vector3(at.x, 0.0, at.z)


func _ready() -> void:
	# Only the host detects. Polling (not body_entered) also catches enemies
	# that spawn or get pushed inside the zone without "entering" it.
	set_physics_process(multiplayer.is_server())
	if multiplayer.is_server():
		print("[Trap] %s armed at %s" % [name, position])
		_lifetime_timer.one_shot = true
		_lifetime_timer.timeout.connect(_expire)
		_lifetime_timer.start(ability.lifetime)


# Host only.
func _physics_process(_delta: float) -> void:
	var snapped_any := false
	for body in get_overlapping_bodies():
		if body.is_in_group("enemies") and body.hp > 0:
			body.host_apply_root(ability.root_duration)
			snapped_any = true
	if snapped_any:
		print("[Trap] %s triggered" % name)
		_consume.rpc()


# Host only.
func _expire() -> void:
	_consume.rpc()


@rpc("authority", "call_local", "reliable")
func _consume() -> void:
	queue_free()
