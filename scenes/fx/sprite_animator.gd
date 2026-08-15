class_name SpriteAnimator
extends Node
## Gives a billboard sprite the motion a single static frame cannot: a walk
## bob, a facing flip, a white flash when hit and a kick-back when it attacks.
##
## This is procedural rather than drawn on purpose. Frame animation for six
## characters is two dozen more hand-drawn pixel maps and belongs with the real
## art; the *feel* of a character being alive is mostly motion, not frames, and
## motion is free. A sprite that bobs when it walks and recoils when it shoots
## reads as animated even though it only ever has one frame.
##
## Nothing here is networked, and nothing here needs to be. Every input is
## state that is already replicated for gameplay reasons — `velocity` is in the
## replication config of both player.tscn and enemy.tscn, and hp arrives via
## `_sync_hp` — so each peer animates from what it already knows. That is also
## why the flash triggers on *observing* an hp drop rather than on dealing
## damage: the observation happens on every peer, the damage only on the host.
##
## It runs its own `_process` because none of its owners have a callback that
## fires everywhere: a Player physics-processes only on its owning client and
## processes only on the host, and an Enemy does not physics-process on clients
## at all. A component driven by any of those would animate on one peer and
## leave the character sliding rigidly on the others. As a plain child node it
## is ungated, and it reads the body handed to it by `setup()` rather than
## reaching up the tree for it.

## Peak height of the walk bob, in world units. Small: this reads as a footfall,
## and anything larger reads as the character hovering.
@export var bob_height := 0.06

## World units travelled per full two-step bob cycle. Tied to distance rather
## than to time so the bob stays locked to the stride at any speed — a
## time-based bob visibly slides against the ground when a character speeds up.
@export var bob_cycle_distance := 1.3

## Below this speed (world units/sec) the character is treated as standing.
@export var idle_speed_threshold := 0.15

## How much the drop shadow shrinks at the top of a step, as a fraction.
##
## The obvious place for squash-and-stretch is the sprite, and on a billboard
## it is not available: billboard modes rebuild the model matrix from the
## camera and discard the node's scale unless `billboard_keep_scale` is set,
## which Sprite3D does not expose. Scaling the sprite would have compiled, run,
## and done nothing. The shadow is an ordinary un-billboarded mesh, so it CAN
## scale — and a shadow that tightens as a character rises sells the bounce
## better than squashing the character would, because it also says how far off
## the ground they are.
@export var shadow_squash := 0.22

## Seconds the white hit-flash lasts.
@export var flash_time := 0.11

## How far, in world units, the sprite kicks back when it attacks, and for how
## long. This is what makes a shot look fired rather than merely spawned.
@export var recoil_distance := 0.1
@export var recoil_time := 0.16

## Set false by the owner for a character that is present but not walking — a
## downed player is still on the ground, they are just not taking steps.
var upright := true

var _sprite: Sprite3D
var _body: CharacterBody3D
var _shadow: MeshInstance3D
var _rest_position := Vector3.ZERO
## Distance travelled, which drives the bob phase.
var _stride := 0.0
var _flash_left := 0.0
var _recoil_left := 0.0
var _recoil_dir := Vector3.ZERO


## Injected by the owner once its Sprite3D exists. The rest position is captured
## here rather than exported because it is a fact about the scene (the sprite's
## authored height above the feet), not a tunable.
func setup(sprite: Sprite3D, body: CharacterBody3D, shadow: MeshInstance3D = null) -> void:
	_sprite = sprite
	_body = body
	_shadow = shadow
	_rest_position = sprite.position


## Call when this character is seen to lose hp — on every peer, not just the
## host. Safe to call when already flashing; it simply restarts.
func flash() -> void:
	_flash_left = flash_time


## Call when this character attacks, with the direction the attack is aimed.
## The sprite kicks the opposite way and settles back.
func recoil(direction: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() <= 0.0:
		return
	_recoil_dir = flat.normalized()
	_recoil_left = recoil_time


## What the owner must multiply into `sprite.modulate`. Never sets modulate
## itself: WorldLight hand-drives every billboard's tint each frame and the
## survival tints compose on top of that, so a component that assigned modulate
## would either be overwritten or would silently erase the lighting.
func tint_multiplier() -> Color:
	if _flash_left <= 0.0:
		return Color.WHITE
	# Squared so the flash spikes hard and falls off quickly, which reads as an
	# impact; a linear fade reads as the character glowing.
	var strength := pow(_flash_left / flash_time, 2.0)
	return Color.WHITE.lerp(Color(4.0, 3.6, 3.2), strength)


func _process(delta: float) -> void:
	# setup() lands during the owner's _ready, which may be after this node's;
	# until then there is nothing to animate.
	if _sprite == null or _body == null:
		return

	_flash_left = maxf(_flash_left - delta, 0.0)
	_recoil_left = maxf(_recoil_left - delta, 0.0)

	# Velocity is replicated for both players and enemies, so this is the same
	# number on every peer and the animation matches everywhere for free.
	var flat := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	var speed := flat.length()

	# Face the way we are going — but "the way we are going" has to be measured
	# on SCREEN, not in world space. The camera is yawed 45 degrees, so testing
	# velocity.x alone would flip characters at the wrong quarter of the compass
	# and they would moonwalk through two of the eight directions.
	if speed > idle_speed_threshold:
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			_sprite.flip_h = camera.global_basis.x.dot(flat) < 0.0

	var offset := Vector3.ZERO
	var lift := 0.0
	if speed > idle_speed_threshold and upright:
		_stride += speed * delta
		# abs(sin) rather than sin: a foot hits the ground twice per cycle, so
		# the sprite should rise and fall twice, never dip below its rest height.
		var phase := _stride / maxf(bob_cycle_distance, 0.01) * TAU
		lift = absf(sin(phase))
		offset.y = lift * bob_height
	else:
		# Reset so the next step starts from a footfall rather than resuming
		# wherever the last one was interrupted.
		_stride = 0.0

	if _recoil_left > 0.0:
		offset -= _recoil_dir * recoil_distance * (_recoil_left / recoil_time)

	_sprite.position = _rest_position + offset
	if _shadow != null:
		var shrink := 1.0 - lift * shadow_squash
		_shadow.scale = Vector3(shrink, 1.0, shrink)
