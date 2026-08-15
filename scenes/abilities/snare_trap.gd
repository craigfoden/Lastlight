class_name SnareTrap
extends Area3D
## A ground deployable. Two behaviours out of the same node, chosen by data:
##   root_duration > 0 -> a snare. Roots what steps on it, then is consumed.
##   tick_damage   > 0 -> a sigil. Burns everything standing on it every
##                        `tick_interval` and keeps burning for its lifetime.
## A deployable with both roots once and is consumed, root winning, because a
## consumed node cannot go on burning.
##
## Spawned on all peers with a deterministic name so the host can broadcast the
## consume; only the host detects, roots, and damages. The look is a flat
## ground decal (the world3d decor idiom), the trigger a squat cylinder.

var ability: AbilityType

var _burn_cd := 0.0  # host-only: seconds until the next burn tick

@onready var _lifetime_timer: Timer = $LifetimeTimer
@onready var _decal: MeshInstance3D = $Decal


func setup(new_ability: AbilityType, at: Vector3) -> void:
	ability = new_ability
	position = Vector3(at.x, 0.0, at.z)


func _ready() -> void:
	if ability.decal_texture != null:
		# A fresh material per instance, not the scene's: sub-resources
		# authored in a .tscn are shared across every instance, so swapping the
		# texture on one would repaint every other deployable on the ground.
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_texture = ability.decal_texture
		material.roughness = 1.0
		_decal.material_override = material
	# Only the host detects. Polling (not body_entered) also catches enemies
	# that spawn or get pushed inside the zone without "entering" it.
	set_physics_process(multiplayer.is_server())
	if multiplayer.is_server():
		print("[Trap] %s armed at %s" % [name, position])
		_lifetime_timer.one_shot = true
		_lifetime_timer.timeout.connect(_expire)
		_lifetime_timer.start(ability.lifetime)


# Host only.
func _physics_process(delta: float) -> void:
	_burn_cd = maxf(_burn_cd - delta, 0.0)
	var roots: bool = ability.root_duration > 0.0
	var burns: bool = ability.tick_damage > 0 and _burn_cd <= 0.0
	if not roots and not burns:
		return
	var caught := 0
	for body in get_overlapping_bodies():
		if not body.is_in_group("enemies") or body.hp <= 0:
			continue
		if roots:
			body.host_apply_root(ability.root_duration)
		if burns:
			body.host_take_damage(ability.tick_damage)
		caught += 1
	if caught == 0:
		return
	if burns:
		_burn_cd = ability.tick_interval
		print("[Trap] %s burned %d" % [name, caught])
	if roots:
		# A snare spends itself on the first thing it catches.
		print("[Trap] %s triggered" % name)
		_consume.rpc()


# Host only.
func _expire() -> void:
	_consume.rpc()


@rpc("authority", "call_local", "reliable")
func _consume() -> void:
	queue_free()
