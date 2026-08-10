class_name GlowTower
extends StaticBody3D
## The village heart in the 3D world: mesh column, emissive gem, and the tower
## light as a real OmniLight3D. Same host-authoritative hp lane as the 2D
## GlowTower — if hp reaches zero, the necromancer descends and the run is lost.
##
## The node sits at the ORIGIN like the 2D tower (enemy attack range and the
## safe zone measure distance to global_position — 2D parity depends on it);
## the column/gem/light/collision children are offset to z = -1 so the mesh
## still covers the TOWER_CELLS footprint north of the heart (phase 6, was
## previously the node itself at (0, 0, -1)).

## Fired on every peer when hp first reaches zero.
signal destroyed

## No stack we have tested renders a trustworthy shadowed omni, so the tower
## light never casts shadows. The failure is always the same: the light's whole
## range box over-darkens below ambient, so the pool floor renders BLACK — the
## opposite of a light. Observed on the Compatibility fallback (phase 1), on
## macOS/Metal in cube AND dual-paraboloid modes (phase 7), on Windows/Vulkan
## Forward+ in daylight (Vega M, phase 2) and — the last stack anyone still
## trusted — on Windows/Vulkan Forward+ at night too (Vega M, 2026-08-10:
## a hard-edged black diamond over the entire pool, gone the instant
## shadow_enabled is cleared with every other variable held fixed).
## Flip to true only for a stack whose night pool has been eyeballed clean.
const SHADOWED_OMNIS_TRUSTED := false

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


## The single gate for tower-light shadows — WorldLight calls this every frame
## with its night-only test, and SHADOWED_OMNIS_TRUSTED vetoes it everywhere.
func set_light_shadows(enabled: bool) -> void:
	_light.shadow_enabled = enabled and SHADOWED_OMNIS_TRUSTED


## WorldLight breathes the pool's brightness through the day cycle.
func set_light_energy(energy: float) -> void:
	_light.light_energy = energy


## WorldLight resizes the light through the day cycle: the wide daylight
## bubble by day contracts into the tight night pool at dusk.
func set_light_range(range_cells: float) -> void:
	_light.omni_range = range_cells


## How far the light reaches right now — sprites inside warm toward its color.
func light_range() -> float:
	return _light.omni_range


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
