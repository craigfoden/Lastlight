extends Node3D
## Session root for the 3D game (docs/PORT_PLAN.md phases 2-3): owns the world
## shell (ground, sun, glow tower, WorldGen3D scatter) and the multiplayer
## skeleton — spawns/despawns players with the same connect-after-load flow as
## the 2D game.gd. Still to port: harvest routing (phase 4), building (5),
## waves/combat (6), day/night light + join refusal at night (7). Launch:
##   godot -- --game3d --host          (or --game3d --join=<ip>)
##   godot --rendering-method forward_plus --path . res://scenes/game3d/game3d.tscn
## Dev args (after --): --quit-after-sec=N, --screenshot-at=a,b (windowed),
## --auto-walk (local player strolls), --log-players-after-sec=a,b,
## --auto-harvest (teleport-harvest loop, exercises the RPC chain).

const MAIN_MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"
const PlayerScene := preload("res://scenes/player3d/player_3d.tscn")

## Players spawn on a ring around the glowing tower (the 2D game's 96 px), in cells.
@export var spawn_radius := 3.0

## Seconds a joining client waits before giving up. ENet itself can take 30+
## seconds to admit failure, which reads as a hang — we enforce our own limit.
@export var join_timeout := 10.0

var _auto_walk := false

@onready var players: Node3D = $Players
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var team_materials: TeamMaterials = $TeamMaterials
@onready var hud: Hud3D = $HUD


func _ready() -> void:
	# Custom spawn: the host decides spawn data, every peer (host included)
	# builds the node from it identically — position and name are guaranteed
	# correct before the node enters the tree, no sync race.
	player_spawner.spawn_function = _build_player
	hud.setup(team_materials)
	_parse_dev_args()
	# Harvests announce themselves; the game routes them to the shared pool
	# (signals up, calls down). The signal only fires on the host.
	for node in get_tree().get_nodes_in_group("resource_nodes"):
		node.harvested.connect(_on_resource_harvested)
	Network.connection_failed.connect(_return_to_menu.bind("Could not reach the host."))
	Network.server_ended.connect(_return_to_menu.bind("The host ended the game."))
	match Network.start_mode:
		Network.StartMode.JOIN:
			hud.show_connecting(true)
			multiplayer.connected_to_server.connect(hud.show_connecting.bind(false))
			Network.join_game(Network.pending_address)
			_start_join_timeout()
		_:
			# HOST from the menu, or NONE when running this scene directly
			# from the CLI or editor (F6) — both mean: be the host, even solo.
			var err := Network.host_game()
			if err != OK:
				_return_to_menu.call_deferred("Could not host (is the port already in use?)")
				return
			multiplayer.peer_connected.connect(_on_peer_connected)
			multiplayer.peer_disconnected.connect(_on_peer_disconnected)
			_spawn_player(1)
	print("[Game3D] World shell ready (%s / %s)" % [
			RenderingServer.get_current_rendering_method(),
			RenderingServer.get_current_rendering_driver_name()])


# Host only. The joiner's scene is already loaded (clients connect from inside
# it), so it is safe to spawn their player and push them the state that is not
# covered by synchronizers. (Night-phase join refusal returns with phase 7 —
# there is no night here yet.)
func _on_peer_connected(peer_id: int) -> void:
	_spawn_player(peer_id)
	team_materials.host_send_snapshot(peer_id)
	for node in get_tree().get_nodes_in_group("resource_nodes"):
		node.host_send_snapshot(peer_id)


func _on_resource_harvested(material_type: MaterialType, count: int) -> void:
	team_materials.host_add(material_type.id, count)


func _on_peer_disconnected(peer_id: int) -> void:
	if players.has_node(str(peer_id)):
		# Freeing on the host makes the MultiplayerSpawner despawn it everywhere.
		players.get_node(str(peer_id)).queue_free()


# Host only: pick spawn data and tell the spawner to build it everywhere.
func _spawn_player(peer_id: int) -> void:
	var angle := players.get_child_count() * TAU / float(Network.MAX_PLAYERS)
	player_spawner.spawn({
		"peer_id": peer_id,
		"position": Vector3(spawn_radius, 0, 0).rotated(Vector3.UP, angle),
	})


# Runs on every peer when the spawner (re)creates a player.
func _build_player(data: Dictionary) -> Node:
	var player := PlayerScene.instantiate() as Player3D
	# The node name doubles as the owner's peer id (see player_3d.gd).
	player.name = str(data.peer_id)
	player.position = data.position
	player.auto_walk = _auto_walk and data.peer_id == multiplayer.get_unique_id()
	return player


# A child Timer (not a SceneTreeTimer) so it is freed with the scene and can
# never fire into a dead context after we've already left for the menu.
func _start_join_timeout() -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = join_timeout
	timer.timeout.connect(_on_join_timeout)
	add_child(timer)
	timer.start()


func _on_join_timeout() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		_return_to_menu("Could not reach the host (timed out).")


func _return_to_menu(reason: String) -> void:
	print("[Game3D] Returning to menu: %s" % reason)
	Network.last_error = reason
	Network.leave_game()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# --- dev harness (mirrors game.gd's hooks) -----------------------------------

func _parse_dev_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot-at="):
			for stamp in arg.get_slice("=", 1).split(","):
				_save_screenshot_after(float(stamp))
		elif arg.begins_with("--quit-after-sec="):
			get_tree().create_timer(float(arg.get_slice("=", 1))).timeout.connect(
					func() -> void: get_tree().quit())
		elif arg == "--auto-walk":
			_auto_walk = true
		elif arg == "--auto-harvest":
			_start_auto_harvest()
		elif arg.begins_with("--log-players-after-sec="):
			for stamp in arg.get_slice("=", 1).split(","):
				_log_players_after(float(stamp))


# Smoke-test hook (godot -- --auto-harvest): every 2 s, teleport the local
# player to the nearest stocked resource node and harvest it. Exercises
# movement sync + the whole request -> validate -> broadcast chain headlessly.
func _start_auto_harvest() -> void:
	var timer := Timer.new()
	timer.wait_time = 2.0
	timer.autostart = true
	timer.timeout.connect(_auto_harvest_tick)
	add_child(timer)


func _auto_harvest_tick() -> void:
	var me: Player3D = players.get_node_or_null(str(multiplayer.get_unique_id()))
	if me == null or not me.is_multiplayer_authority():
		return
	var nearest: ResourceNode3D = null
	var best := INF
	for node in get_tree().get_nodes_in_group("resource_nodes"):
		if node.amount <= 0:
			continue
		var dist := me.global_position.distance_squared_to(node.global_position)
		if dist < best:
			best = dist
			nearest = node
	if nearest == null:
		return
	me.global_position = nearest.global_position + Vector3(0.625, 0, 0)
	me.try_harvest()


# Dev hook: print every player's position, so headless smoke runs can assert
# that a remote player's replicated position actually changes over time.
func _log_players_after(delay_sec: float) -> void:
	await get_tree().create_timer(delay_sec).timeout
	for player in players.get_children():
		print("[Game3D] t=%d player %s at %v" % [int(delay_sec), player.name, player.position])


func _save_screenshot_after(delay_sec: float) -> void:
	await get_tree().create_timer(delay_sec).timeout
	var image := get_viewport().get_texture().get_image()
	var path := "user://game3d_shot_%d.png" % int(delay_sec)
	image.save_png(path)
	print("[Game3D] Screenshot saved to %s (%d fps)" % [
			ProjectSettings.globalize_path(path), Engine.get_frames_per_second()])
