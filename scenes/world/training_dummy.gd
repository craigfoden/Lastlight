class_name TrainingDummy
extends StaticBody2D
## Practice target for towers until real enemies land (session 3).
## Host-authoritative hp, broadcast to every peer; respawns after a delay.

@export var max_hp := 20
@export var respawn_seconds := 5.0

var hp := 0:
	set(value):
		hp = value
		_update_appearance()

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _respawn_timer: Timer = $RespawnTimer


func _ready() -> void:
	hp = max_hp
	if multiplayer.is_server():
		_respawn_timer.wait_time = respawn_seconds
		_respawn_timer.one_shot = true
		_respawn_timer.timeout.connect(_host_respawn)


## Host only: towers (and later, players) deal damage through this.
func host_take_damage(amount: int) -> void:
	if not multiplayer.is_server() or hp <= 0:
		return
	var new_hp := maxi(hp - amount, 0)
	_sync_hp.rpc(new_hp)
	if new_hp == 0:
		print("[Dummy] %s destroyed, respawning in %.0f s" % [name, respawn_seconds])
		_respawn_timer.start()


## Host only: bring a late joiner up to date.
func host_send_snapshot(peer_id: int) -> void:
	_sync_hp.rpc_id(peer_id, hp)


func _host_respawn() -> void:
	_sync_hp.rpc(max_hp)


@rpc("authority", "call_local", "reliable")
func _sync_hp(new_hp: int) -> void:
	hp = new_hp


func _update_appearance() -> void:
	if _sprite == null:
		return
	visible = hp > 0
	if hp > 0:
		# Fade as it takes hits, so damage is readable without a health bar.
		_sprite.modulate.a = lerpf(0.35, 1.0, float(hp) / float(maxi(max_hp, 1)))
