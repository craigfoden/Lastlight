extends Node3D
## Session root for the 3D game (docs/PORT_PLAN.md phases 2-6): owns the world
## shell (ground, sun, glow tower, WorldGen3D scatter), the multiplayer
## skeleton — spawns/despawns players with the same connect-after-load flow as
## the 2D game.gd — and mediates between the day/night cycle, the waves, the
## shared material pool, and the HUD. Still to port: day/night light (7). Launch:
##   godot -- --game3d --host          (or --game3d --join=<ip>)
##   godot --rendering-method forward_plus --path . res://scenes/game3d/game3d.tscn
## Dev args (after --): --quit-after-sec=N, --screenshot-at=a,b (windowed),
## --auto-walk (local player strolls), --log-players-after-sec=a,b,
## --auto-harvest (teleport-harvest loop, exercises the RPC chain),
## --auto-build / --auto-block-test / --grant-materials=... / --auto-fight /
## --hurt-test / --tower-hp=N / --fast-cycle / --cycle=day:night /
## --final-day=N (same as 2D).

const MAIN_MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"
const PlayerScene := preload("res://scenes/player3d/player_3d.tscn")

## The glowing tower's footprint on the build grid (solid, unbuildable) and
## the walkable cell at its base that enemies path toward. Same cells as the
## 2D game — the tower sits at world (0, 0, -1) so its 2x2 base covers them.
const TOWER_CELLS: Array[Vector2i] = [
	Vector2i(-1, -2), Vector2i(0, -2), Vector2i(-1, -1), Vector2i(0, -1),
]
const HEART_CELL := Vector2i(0, 0)

## Players spawn on a ring around the glowing tower (the 2D game's 96 px), in cells.
@export var spawn_radius := 3.0

## Seconds a joining client waits before giving up. ENet itself can take 30+
## seconds to admit failure, which reads as a hang — we enforce our own limit.
@export var join_timeout := 10.0

## Chest contents per player per survived night (v1: straight into the
## shared pool; per-player gear loot arrives with gear tiers).
@export var chest_wood := 2
@export var chest_stone := 1
@export var chest_essence := 1

## Run-XP formula (same numbers as the 2D game).
@export var xp_per_night := 100
@export var xp_victory_bonus := 300

var run_over := false
var _auto_walk := false

@onready var players: Node3D = $Players
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var day_night: DayNightCycle = $DayNight
@onready var team_materials: TeamMaterials = $TeamMaterials
@onready var hud: Hud3D = $HUD
@onready var build_manager: BuildManager3D = $BuildManager
@onready var build_controller: BuildController3D = $BuildController
@onready var build_menu: BuildMenu3D = $BuildMenu
@onready var spawn_openings: Node3D = $World/SpawnOpenings
@onready var wave_director: WaveDirector3D = $WaveDirector
@onready var world_gen: WorldGen3D = $World/WorldGen
@onready var glow_tower: GlowTower3D = $World/GlowTower
@onready var run_end_screen: RunEndScreen = $RunEndScreen


func _ready() -> void:
	# Custom spawn: the host decides spawn data, every peer (host included)
	# builds the node from it identically — position and name are guaranteed
	# correct before the node enters the tree, no sync race.
	player_spawner.spawn_function = _build_player
	hud.setup(day_night, team_materials, glow_tower)

	var opening_cells: Array[Vector2i] = []
	var spawn_positions: Array[Vector3] = []
	for marker in spawn_openings.get_children():
		opening_cells.append(build_manager.world_to_cell(marker.global_position))
		spawn_positions.append(marker.global_position)
	# The tower footprint plus every solid prop WorldGen scattered are permanent
	# unbuildable, unwalkable cells (WorldGen already ran — it is a child).
	var scenery_cells: Array[Vector2i] = TOWER_CELLS.duplicate()
	for node in get_tree().get_nodes_in_group("obstacles"):
		scenery_cells.append(build_manager.world_to_cell(node.global_position))
	build_manager.setup(team_materials, opening_cells, HEART_CELL, scenery_cells)
	build_controller.setup(build_manager)
	build_menu.setup(build_manager, build_controller, team_materials)
	wave_director.setup(day_night, build_manager, glow_tower, spawn_positions,
			world_gen.safe_radius)
	wave_director.night_survived.connect(_on_night_survived)
	glow_tower.destroyed.connect(_on_tower_destroyed)
	run_end_screen.menu_requested.connect(_return_to_menu.bind(""))

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
			for arg in OS.get_cmdline_user_args():
				# Dev cheat for testing builds: --grant-materials=wood:10,stone:10
				if arg.begins_with("--grant-materials="):
					for pair in arg.get_slice("=", 1).split(","):
						team_materials.host_add(
								StringName(pair.get_slice(":", 0)),
								int(pair.get_slice(":", 1)))
				elif arg.begins_with("--tower-hp="):
					# Dev: shrink the tower's health to test defeat quickly.
					glow_tower.max_hp = int(arg.get_slice("=", 1))
					glow_tower.hp = glow_tower.max_hp
	print("[Game3D] World shell ready (%s / %s)" % [
			RenderingServer.get_current_rendering_method(),
			RenderingServer.get_current_rendering_driver_name()])


# Host only. The joiner's scene is already loaded (clients connect from inside
# it), so it is safe to spawn their player and push them the state that is not
# covered by synchronizers.
func _on_peer_connected(peer_id: int) -> void:
	if day_night.phase == DayNightCycle.Phase.NIGHT or run_over:
		# Design rule: joining is day-phase only. Kicking here (app layer)
		# is deliberate — ENet's refuse_new_connections flag half-works and
		# leaves the client in limbo instead (see GOTCHAS).
		print("[Game3D] Refused join from peer %d (night assault in progress)" % peer_id)
		(multiplayer as SceneMultiplayer).disconnect_peer(peer_id)
		return
	_spawn_player(peer_id)
	team_materials.host_send_snapshot(peer_id)
	glow_tower.host_send_snapshot(peer_id)
	for node in get_tree().get_nodes_in_group("resource_nodes"):
		node.host_send_snapshot(peer_id)
	for node in get_tree().get_nodes_in_group("enemies"):
		node.host_send_snapshot(peer_id)
	for node in get_tree().get_nodes_in_group("players"):
		node.host_send_snapshot(peer_id)
	# Placed buildings need no snapshot: their spawner replays them.


# Host only (WaveDirector emits at dawn on the host).
func _on_night_survived(night: int) -> void:
	if run_over:
		return
	# One chest per player; contents go into the shared pool for now.
	var chests := Network.player_count()
	team_materials.host_add(&"wood", chest_wood * chests)
	team_materials.host_add(&"stone", chest_stone * chests)
	team_materials.host_add(&"essence_faint", chest_essence * chests)
	print("[Game3D] Night %d survived - %d chest(s) opened" % [night, chests])
	if night >= day_night.final_day:
		_end_run.rpc(true, night)


# Fires on every peer (hp is replicated); only the host declares the loss.
func _on_tower_destroyed() -> void:
	if multiplayer.is_server() and not run_over:
		_end_run.rpc(false, day_night.day_number)


@rpc("authority", "call_local", "reliable")
func _end_run(victory: bool, nights: int) -> void:
	if run_over:
		return
	run_over = true
	day_night.set_process(false)
	wave_director.stop()
	build_controller.select(null)
	var xp := nights * xp_per_night + (xp_victory_bonus if victory else 0)
	# Everyone banks their own XP into their own local profile.
	Profile.bank_run(Network.local_player_class, xp)
	run_end_screen.show_results(victory, nights, xp)
	print("[Game3D] Run ended: %s after night %d (+%d XP)"
			% ["VICTORY" if victory else "DEFEAT", nights, xp])


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
		elif arg == "--auto-build":
			_run_auto_build()
		elif arg == "--auto-block-test":
			_run_auto_block_test()
		elif arg == "--auto-fight":
			_start_auto_fight()
		elif arg == "--hurt-test":
			_start_hurt_test()
		elif arg == "--fast-cycle":
			# Dev helper: 10 s days / 6 s nights to see dusk and night quickly.
			# Pass it to every instance so clients predict time correctly too.
			day_night.day_length = 10.0
			day_night.night_length = 6.0
		elif arg.begins_with("--cycle="):
			# Dev helper: custom pacing, e.g. --cycle=8:60 (day:night seconds).
			day_night.day_length = float(arg.get_slice("=", 1).get_slice(":", 0))
			day_night.night_length = float(arg.get_slice("=", 1).get_slice(":", 1))
		elif arg.begins_with("--final-day="):
			# Dev helper: shorter runs, e.g. --final-day=1 to win after night 1.
			day_night.final_day = int(arg.get_slice("=", 1))
		elif arg.begins_with("--log-players-after-sec="):
			for stamp in arg.get_slice("=", 1).split(","):
				_log_players_after(float(stamp))


# Smoke-test hook (godot -- --auto-fight): stand on the eastern approach lane
# and cast the whole Ranger kit at the nearest monster. Exercises aim/cast
# RPCs, projectiles, piercing, and the snare trap. Same logic as the 2D hook,
# distances in cells (2D px / 32).
func _start_auto_fight() -> void:
	var timer := Timer.new()
	timer.wait_time = 0.6
	timer.autostart = true
	timer.timeout.connect(_auto_fight_tick)
	add_child(timer)


func _auto_fight_tick() -> void:
	var me: Player3D = players.get_node_or_null(str(multiplayer.get_unique_id()))
	if me == null or not me.is_multiplayer_authority():
		return
	# Stand ON the eastern approach lane (ask the pathfinder — a rock makes
	# A* detour a row, so a hardcoded spot misses the actual lane).
	var lane := build_manager.path_to_heart(Vector3(49.5, 0.0, 0.5))
	var stand := Vector3(3.125, 0.0, 0.5)
	for point in lane:
		if absf(point.x - 3.125) < 0.53:
			stand = Vector3(point.x, 0.0, point.y)
			break
	me.global_position = stand
	var nearest: Node3D = null
	var best := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.hp <= 0:
			continue
		var dist: float = me.global_position.distance_squared_to(enemy.global_position)
		if dist < best:
			best = dist
			nearest = enemy
	if nearest == null:
		return
	var direction := me.global_position.direction_to(nearest.global_position)
	var distance := me.global_position.distance_to(nearest.global_position)
	# Hold fire until they're ON the trap, so the root gets tested too.
	if me.cooldown_remaining(me.class_type.ability_2) <= 0.0 and distance < 5.0:
		me.try_cast_toward(me.class_type.ability_2, direction)
	elif me.cooldown_remaining(me.class_type.ability_1) <= 0.0 and distance < 1.875:
		me.try_cast_toward(me.class_type.ability_1, direction)
	elif distance < 1.875:
		me.try_cast_toward(me.class_type.basic_attack, direction)


# Smoke-test hook (godot -- --hurt-test): the host chips every player's hp on a
# timer so the downed -> respawn (and revive, when a teammate is near) path can
# be exercised headlessly. Harmless otherwise (guarded to the host).
func _start_hurt_test() -> void:
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_hurt_test_tick)
	add_child(timer)


func _hurt_test_tick() -> void:
	if not multiplayer.is_server():
		return
	for node in get_tree().get_nodes_in_group("players"):
		node.host_take_damage(15)


# Smoke-test hook (godot -- --auto-build): drive the real place/reject/sell
# RPC chain on a fixed timeline; smoke tests assert on the [Build] logs.
# Same cells as the 2D hook.
func _run_auto_build() -> void:
	await get_tree().create_timer(4.0).timeout
	build_manager.request_place.rpc_id(1, &"wall", Vector2i(3, 3))
	await get_tree().create_timer(2.0).timeout
	build_manager.request_place.rpc_id(1, &"sentry_tower", Vector2i(3, -3))
	await get_tree().create_timer(1.0).timeout
	build_manager.request_place.rpc_id(1, &"arrow_turret", Vector2i(2, -3))
	await get_tree().create_timer(1.0).timeout
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
	# Wait for a full frame first (docs: tutorials/rendering/viewports.rst) —
	# without it the capture can be a STALE frame (seen on macOS/Metal).
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "user://game3d_shot_%d.png" % int(delay_sec)
	image.save_png(path)
	print("[Game3D] Screenshot saved to %s (%d fps)" % [
			ProjectSettings.globalize_path(path), Engine.get_frames_per_second()])
