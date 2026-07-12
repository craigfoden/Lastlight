class_name TeamMaterials
extends Node
## The shared team pool of materials (used later for building AND gear costs).
## Host-authoritative: only the host mutates the pool, then broadcasts the
## whole dictionary to everyone. It is tiny (a handful of ints), so sending it
## whole keeps every peer trivially consistent.

signal pool_changed

## material id (StringName) -> count. Identical on every peer.
var pool := {}


func count_of(material_id: StringName) -> int:
	return pool.get(material_id, 0)


## Host only: award materials to the team.
func host_add(material_id: StringName, count: int) -> void:
	assert(multiplayer.is_server(), "Only the host mutates the material pool")
	var updated := pool.duplicate()
	updated[material_id] = int(updated.get(material_id, 0)) + count
	_receive_pool.rpc(updated)


## Host only: bring a late joiner up to date.
func host_send_snapshot(peer_id: int) -> void:
	_receive_pool.rpc_id(peer_id, pool)


@rpc("authority", "call_local", "reliable")
func _receive_pool(new_pool: Dictionary) -> void:
	pool = new_pool
	pool_changed.emit()
	print("[TeamMaterials] Pool: %s" % pool)
