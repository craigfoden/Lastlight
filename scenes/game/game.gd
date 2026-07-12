extends Node2D
## Session root: owns the world, spawns/despawns players, and mediates between
## the day/night cycle, the shared material pool, and the HUD.
##
## Both host and clients load this same scene. The host then opens the server;
## clients connect only *after* the scene is in the tree, so replication
## packets can never arrive before the nodes they target exist.

const MAIN_MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"
const PlayerScene := preload("res://scenes/player/player.tscn")

## The glowing tower's footprint on the build grid (solid, unbuildable) and
## the walkable cell at its base that enemies path toward. Hardcoded for the
## session-1 static map; map generation will compute these later.
const TOWER_CELLS: Array[Vector2i] = [
	Vector2i(-1, -2), Vector2i(0, -2), Vector2i(-1, -1), Vector2i(0, -1),
]
const HEART_CELL := Vector2i(0, 0)

## Players spawn on a ring around the glowing tower (which sits at the origin).
@export var spawn_radius := 96.0

## Seconds a joining client waits before giving up. ENet itself can take 30+
## seconds to admit failure, which reads as a hang — we enforce our own limit.
@export var join_timeout := 10.0

@onready var players: Node2D = $Players
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var day_night: DayNightCycle = $DayNight
@onready var team_materials: TeamMaterials = $TeamMaterials
@onready var world_light: CanvasModulate = $WorldLight
@onready var hud: Hud = $HUD
@onready var build_manager: BuildManager = $BuildManager
@onready var build_controller: BuildController = $BuildController
@onready var build_menu: BuildMenu = $BuildMenu
@onready var spawn_openings: Node2D = $World/SpawnOpenings


func _ready() -> void:
	# Custom spawn: the host decides spawn data, every peer (host included)
	# builds the node from it identically — position and name are guaranteed
	# correct before the node enters the tree, no sync race.
	player_spawner.spawn_function = _build_player
	hud.setup(day_night, team_materials)

	var opening_cells: Array[Vector2i] = []
	for marker in spawn_openings.get_children():
		opening_cells.append(build_manager.world_to_cell(marker.global_position))
	build_manager.setup(team_materials, opening_cells, HEART_CELL, TOWER_CELLS)
	build_controller.setup(build_manager)
	build_menu.setup(build_manager, build_controller, team_materials)
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
			# from the editor (F6) — both mean: be the host, even solo.
			var err := Network.host_game()
			if err != OK:
				_return_to_menu.call_deferred("Could not host (is the port already in use?)")
				return
			multiplayer.peer_connected.connect(_on_peer_connected)
			multiplayer.peer_disconnected.connect(_on_peer_disconnected)
			_spawn_player(1)
			for arg in OS.get_cmdline_user_args():
				# Dev cheat for testing builds: --grant-materials=wood:10,stone:10
				if arg.begins_with("--grant-materials="):
					for pair in arg.get_slice("=", 1).split(","):
						team_materials.host_add(
								StringName(pair.get_slice(":", 0)),
								int(pair.get_slice(":", 1)))

	if OS.get_cmdline_user_args().has("--auto-build"):
		_run_auto_build()
	if OS.get_cmdline_user_args().has("--auto-block-test"):
		_run_auto_block_test()
	if OS.get_cmdline_user_args().has("--auto-harvest"):
		_start_auto_harvest()
	if OS.get_cmdline_user_args().has("--fast-cycle"):
		# Dev helper: 10 s days / 6 s nights to see dusk and night quickly.
		# Pass it to every instance so clients predict time correctly too.
		day_night.day_length = 10.0
		day_night.night_length = 6.0


func _process(_delta: float) -> void:
	world_light.color = day_night.ambient_color()


# Smoke-test hook (godot -- --auto-build): drive the real place/reject/sell
# RPC chain on a fixed timeline; smoke tests assert on the [Build] logs.
func _run_auto_build() -> void:
	await get_tree().create_timer(4.0).timeout
	build_manager.request_place.rpc_id(1, &"wall", Vector2i(3, 3))
	await get_tree().create_timer(2.0).timeout
	build_manager.request_place.rpc_id(1, &"sentry_tower", Vector2i(3, -3))
	await get_tree().create_timer(2.0).timeout
	# Same cell again: the host must reject it as occupied.
	build_manager.request_place.rpc_id(1, &"wall", Vector2i(3, 3))
	await get_tree().create_timer(4.0).timeout
	build_manager.request_sell.rpc_id(1, Vector2i(3, 3))


# Smoke-test hook (godot -- --auto-block-test): wall in the tower's heart
# cell. Its north side is already tower footprint, so the third wall would
# seal it — the never-block-the-path rule must reject it.
func _run_auto_block_test() -> void:
	await get_tree().create_timer(4.0).timeout
	build_manager.request_place.rpc_id(1, &"wall", Vector2i(1, 0))
	await get_tree().create_timer(1.0).timeout
	build_manager.request_place.rpc_id(1, &"wall", Vector2i(0, 1))
	await get_tree().create_timer(1.0).timeout
	build_manager.request_place.rpc_id(1, &"wall", Vector2i(-1, 0))


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
	var me: Player = players.get_node_or_null(str(multiplayer.get_unique_id()))
	if me == null or not me.is_multiplayer_authority():
		return
	var nearest: ResourceNode = null
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
	me.global_position = nearest.global_position + Vector2(20, 0)
	me.try_harvest()


# Host only. The joiner's Game scene is already loaded (clients connect from
# inside it), so it is safe to spawn their player and push them the state that
# is not covered by synchronizers.
func _on_peer_connected(peer_id: int) -> void:
	_spawn_player(peer_id)
	team_materials.host_send_snapshot(peer_id)
	for node in get_tree().get_nodes_in_group("resource_nodes"):
		node.host_send_snapshot(peer_id)
	for node in get_tree().get_nodes_in_group("enemies"):
		node.host_send_snapshot(peer_id)
	# Placed buildings need no snapshot: their spawner replays them.


func _on_peer_disconnected(peer_id: int) -> void:
	if players.has_node(str(peer_id)):
		# Freeing on the host makes the MultiplayerSpawner despawn it everywhere.
		players.get_node(str(peer_id)).queue_free()


# Host only: pick spawn data and tell the spawner to build it everywhere.
func _spawn_player(peer_id: int) -> void:
	var angle := players.get_child_count() * TAU / float(Network.MAX_PLAYERS)
	player_spawner.spawn({
		"peer_id": peer_id,
		"position": Vector2(spawn_radius, 0).rotated(angle),
	})


# Runs on every peer when the spawner (re)creates a player.
func _build_player(data: Dictionary) -> Node:
	var player := PlayerScene.instantiate()
	# The node name doubles as the owner's peer id (see player.gd).
	player.name = str(data.peer_id)
	player.position = data.position
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


func _on_resource_harvested(material_type: MaterialType, count: int) -> void:
	team_materials.host_add(material_type.id, count)


func _return_to_menu(reason: String) -> void:
	print("[Game] Returning to menu: %s" % reason)
	Network.last_error = reason
	Network.leave_game()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
