class_name GlowTower3D
extends StaticBody3D
## The village heart in the 3D world: mesh column, emissive gem, and the tower
## light as a real OmniLight3D. Same host-authoritative hp lane as the 2D
## GlowTower — if hp reaches zero, the necromancer descends and the run is lost.

## Fired on every peer when hp first reaches zero.
signal destroyed

@export var max_hp := 100

var hp := 0:
	set(value):
		var previous := hp
		hp = value
		if previous > 0 and hp <= 0:
			destroyed.emit()

@onready var _light: OmniLight3D = $Light


func _ready() -> void:
	hp = max_hp
	set_light_shadows(false)


## Cast shadows from the tower light — phase 7 drives this by day phase,
## night only. Off on the Compatibility fallback, where omni shadows render
## their lit region black; off in daylight everywhere, because a shadowed omni
## over-darkens its whole range box on some Vulkan drivers too (Vega M, seen
## in phase 2 — the night look is correct on every tested stack).
func set_light_shadows(enabled: bool) -> void:
	_light.shadow_enabled = (enabled
			and RenderingServer.get_current_rendering_method() != "gl_compatibility")


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
