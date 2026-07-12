class_name GlowTower
extends StaticBody2D
## The village heart. If its hp reaches zero, the necromancer descends and
## the run is lost. Host-authoritative hp, replicated like all discrete state.

## Fired on every peer when hp first reaches zero.
signal destroyed

@export var max_hp := 100

var hp := 0:
	set(value):
		var previous := hp
		hp = value
		if previous > 0 and hp <= 0:
			destroyed.emit()


func _ready() -> void:
	hp = max_hp


## Host only: enemies swing at the tower through this.
func host_take_damage(amount: int) -> void:
	if not multiplayer.is_server() or hp <= 0:
		return
	var new_hp := maxi(hp - amount, 0)
	_sync_hp.rpc(new_hp)
	print("[Tower] hp %d/%d" % [new_hp, max_hp])


## Host only: bring a late joiner up to date.
func host_send_snapshot(peer_id: int) -> void:
	_sync_hp.rpc_id(peer_id, hp)


@rpc("authority", "call_local", "reliable")
func _sync_hp(new_hp: int) -> void:
	hp = new_hp
