class_name MeleeArc
extends Area3D
## An instant melee swing: a wedge of `arc_degrees` centred on the aim, out to
## `melee_range`. Spawned on every peer by the same broadcast with identical
## parameters so each peer draws it locally — but only the host's copy deals
## damage, the same contract as Projectile.
##
## The wedge mesh is built from the ability's own numbers rather than authored
## in the scene, so a 100-degree cleave and a 360-degree slam are one kind with
## two .tres files and no second visual to keep in step.

## Ability data is px-denominated; convert at the boundary (32 px = 1 unit).
const PX_PER_UNIT := 32.0
## Height the wedge is drawn and tested at (enemy capsule centre, as Projectile).
const STRIKE_HEIGHT := 0.5
## Triangles per wedge. Enough that even a full circle reads round.
const MESH_SEGMENTS := 24

var _ability: AbilityType
var _direction := Vector3.RIGHT
var _age := 0.0
## Host-only: enemies this swing has already bitten, so a body cannot be hit
## twice by one swing while the wedge is up.
var _already_hit := {}
var _hit_count := 0

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _shape: CollisionShape3D = $CollisionShape3D


## `from` is the caster's ground position; the strike height is applied here,
## identically on every peer.
func setup(ability: AbilityType, from: Vector3, direction: Vector3) -> void:
	_ability = ability
	_direction = Vector3(direction.x, 0.0, direction.z).normalized()
	position = from + Vector3(0, STRIKE_HEIGHT, 0)


func _ready() -> void:
	var reach := _ability.melee_range / PX_PER_UNIT
	# A fresh shape per swing: sub-resources authored in a scene are shared
	# between instances, so sizing one from ability data would resize every
	# other swing in flight.
	var cylinder := CylinderShape3D.new()
	cylinder.radius = reach
	cylinder.height = 1.0
	_shape.shape = cylinder
	_mesh.mesh = _build_wedge(reach)
	_mesh.basis = Basis.looking_at(_direction)


func _physics_process(delta: float) -> void:
	# Poll for the whole swing rather than striking once on the first tick: a
	# freshly added Area3D has not been through a physics step yet, so its
	# overlaps are still empty on tick one and a single-shot strike always
	# whiffs. Polling also makes the wedge an honest active window — walk into
	# a swing already in progress and it catches you.
	if multiplayer.is_server():
		_host_strike()
	_age += delta
	if _age >= _ability.swing_time:
		# Deterministic lifetime from shared data: every peer frees its own
		# copy at the same moment, so no despawn RPC is needed.
		if _hit_count > 0:
			print("[Ability] %s struck %d" % [_ability.id, _hit_count])
		queue_free()


# Host only: everything inside the wedge takes the hit, once per swing.
func _host_strike() -> void:
	var half_arc := deg_to_rad(_ability.arc_degrees) * 0.5
	for body in get_overlapping_bodies():
		if not body.is_in_group("enemies") or body.hp <= 0:
			continue
		if _already_hit.has(body.get_instance_id()):
			continue
		var to_body: Vector3 = body.global_position - global_position
		to_body.y = 0.0
		# A body directly underfoot has no direction; count it as in front.
		if to_body.length() > 0.01 and _direction.angle_to(to_body) > half_arc:
			continue
		_already_hit[body.get_instance_id()] = true
		body.host_take_damage(_ability.damage)
		if _ability.root_duration > 0.0:
			# A freezing nova is a swing that also holds them: same wedge, same
			# once-per-swing rule, one extra line of data.
			body.host_apply_root(_ability.root_duration)
		_hit_count += 1


# A triangle fan on the XZ plane, opening around -Z (a Node3D's forward, which
# _ready then aims along the swing direction).
func _build_wedge(reach: float) -> ArrayMesh:
	var arc := deg_to_rad(_ability.arc_degrees)
	var vertices := PackedVector3Array([Vector3.ZERO])
	for i in MESH_SEGMENTS + 1:
		var angle := -arc * 0.5 + arc * (float(i) / MESH_SEGMENTS)
		vertices.append(Vector3(sin(angle), 0.0, -cos(angle)) * reach)
	var indices := PackedInt32Array()
	for i in MESH_SEGMENTS:
		indices.append_array([0, i + 1, i + 2])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The look comes from the scene's material_override, which applies to
	# whatever surfaces the mesh turns out to have.
	return mesh
