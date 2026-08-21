extends Node3D
## Session root: owns the world shell (ground, sun, glow tower, WorldGen
## scatter), the multiplayer skeleton — both host and clients load this same
## scene, and clients connect only *after* it is in the tree so replication
## packets can never arrive before the nodes they target exist — and mediates
## between the day/night cycle, the waves, the shared material pool, and the
## HUD. WorldLight turns the cycle into the world's light. Launch:
##   godot -- --host              (or --join=<ip>; the menu routes here too)
## Dev args (after --): --quit-after-sec=N, --screenshot-at=a,b (windowed),
## --auto-walk (local player strolls), --log-players-after-sec=a,b,
## --auto-harvest (teleport-harvest loop, exercises the RPC chain),
## --auto-build / --auto-block-test / --grant-materials=... / --auto-fight /
## --auto-camp / --auto-camp-clear /
## --hurt-test / --tower-hp=N / --fast-cycle / --cycle=day:night /
## --final-day=N / --spawn-at=x,z (start the local player out in the wilds) /
## --world-seed=N (host: rebuild one particular map instead of rolling one).
## Class comes from --class=<id>, parsed on the main menu before we load.

const MAIN_MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"
const TALENT_SCREEN_SCENE := "res://scenes/talents/talent_screen.tscn"
const PlayerScene := preload("res://scenes/player/player.tscn")

## Ability data is px-denominated; convert at the boundary (32 px = 1 cell).
const PX_PER_UNIT := 32.0
## --auto-fight only: how close a target must be before the harness lays a
## deployable, or pops a self-buff. Both are harness pacing, not game balance.
const AUTO_FIGHT_DEPLOY_RANGE := 5.0
const AUTO_FIGHT_BUFF_RANGE := 4.0

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

## Grace period between telling a refused joiner *why* and kicking them. The
## polite path is the refusal RPC (the client bounces itself to the menu with
## the reason); the kick is only the backstop for a client that never acted.
@export var refusal_kick_delay := 1.5

## Chest contents per player per survived night (v1: straight into the
## shared pool; per-player gear loot arrives with gear tiers).
@export var chest_wood := 2
@export var chest_stone := 1
@export var chest_essence := 1

## Run-XP formula (same numbers as the 2D game).
@export var xp_per_night := 100
@export var xp_victory_bonus := 300

var run_over := false
## True once WorldGen has run and everything downstream of it is wired. The host
## reaches this during _ready; a client only after the seed arrives.
var world_ready := false
var _auto_walk := false
var _spawn_at_override := Vector3.ZERO
## Dev override (--world-seed=N): reproduce one particular map. Zero means roll
## a fresh one, which is what a real run does.
var _seed_override := 0

## Host only: peers that connected and passed the join rules but are not yet
## ready to receive a character. peer_id -> { "registered": bool, "world": bool }
## — a joiner needs BOTH before it can be spawned into, and the two arrive
## independently and in either order. `registered` is their name and class
## reaching the roster; `world` is their acknowledgement that they have built
## the map from our seed, without which the snapshot RPCs below would target
## world nodes that do not exist on them yet.
var _pending_spawns := {}

@onready var players: Node3D = $Players
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var day_night: DayNightCycle = $DayNight
@onready var world_light: WorldLight = $WorldLight
@onready var team_materials: TeamMaterials = $TeamMaterials
@onready var hud: Hud = $HUD
@onready var build_manager: BuildManager = $BuildManager
@onready var build_controller: BuildController = $BuildController
@onready var build_menu: BuildMenu = $BuildMenu
@onready var wave_director: WaveDirector = $WaveDirector
@onready var world_gen: WorldGen = $World/WorldGen
@onready var ground: Ground = $World/Ground
@onready var regrowth: Regrowth = $World/Regrowth
@onready var glow_tower: GlowTower = $World/GlowTower
@onready var run_end_screen: RunEndScreen = $RunEndScreen


func _ready() -> void:
	# Custom spawn: the host decides spawn data, every peer (host included)
	# builds the node from it identically — position and name are guaranteed
	# correct before the node enters the tree, no sync race.
	player_spawner.spawn_function = _build_player
	hud.setup(day_night, team_materials, glow_tower)
	wave_director.night_survived.connect(_on_night_survived)
	glow_tower.destroyed.connect(_on_tower_destroyed)
	run_end_screen.menu_requested.connect(_return_to_menu.bind(""))
	run_end_screen.talents_requested.connect(_leave_run_for.bind(TALENT_SCREEN_SCENE))

	_parse_dev_args()
	Network.connection_failed.connect(_return_to_menu.bind("Could not reach the host."))
	Network.server_ended.connect(_return_to_menu.bind("The host ended the game."))
	match Network.start_mode:
		Network.StartMode.JOIN:
			# Nothing world-shaped happens here: the map this client builds has
			# to be the host's map, and we do not know its seed until we have
			# connected. _receive_world_seed picks the thread up.
			hud.show_connecting(true)
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
			Network.player_registered.connect(_on_player_registered)
			# The host is the one who decides what this run's world looks like.
			_begin_world(_seed_override if _seed_override != 0 else _roll_seed())
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
	print("[Game] World shell ready (%s / %s)" % [
			RenderingServer.get_current_rendering_method(),
			RenderingServer.get_current_rendering_driver_name()])


# A run's map. `randomize()` seeds the global rng from the clock; WorldGen's own
# RandomNumberGenerator is separate and takes this number, so generation itself
# stays a pure function of the seed and every peer still lands on the same map
# (the determinism rule in GOTCHAS is about *generation*, not about where the
# seed came from). Kept positive because it also has to read well in a log — a
# player reporting a good map should be able to type it back in.
func _roll_seed() -> int:
	randomize()
	return randi() & 0x7fffffff


# Everything downstream of the world existing, on host and client alike. Split
# out of _ready because a client cannot do any of it until the host's seed has
# arrived — before this runs it has a scene but no map.
func _begin_world(seed_value: int) -> void:
	# The heart is handed to the generator rather than assumed by it: the
	# approach corridors have to *end* somewhere, and this scene is what decides
	# where the tower stands.
	world_gen.generate(seed_value, HEART_CELL)

	# Openings are per-run and WorldGen owns them (they used to be two Marker3Ds
	# in this scene, which cannot work once the lane to the tower has to be
	# cleared by the same pass that chooses where it runs).
	var opening_cells := world_gen.opening_cells
	var spawn_positions := world_gen.opening_positions
	# The tower footprint plus every solid prop WorldGen scattered are permanent
	# unbuildable, unwalkable cells (generate() has just run).
	var scenery_cells: Array[Vector2i] = TOWER_CELLS.duplicate()
	for node in get_tree().get_nodes_in_group("obstacles"):
		scenery_cells.append(build_manager.world_to_cell(node.global_position))
	build_manager.setup(team_materials, opening_cells, HEART_CELL, scenery_cells)
	ground.setup(world_gen)
	# The HUD was set up in _ready with everything that exists before the map
	# does; the map itself has to wait until here, because on a client _ready
	# runs long before the host's seed arrives.
	hud.setup_world(world_gen)
	build_controller.setup(build_manager)
	build_menu.setup(build_manager, build_controller, team_materials)
	wave_director.setup(day_night, build_manager, glow_tower, spawn_positions,
			world_gen.safe_radius)
	world_light.setup(day_night, $Sun, $WorldEnvironment, glow_tower)
	# Wired on every peer, silent on all but the host (see its class doc).
	regrowth.setup(day_night, build_manager)
	# Camps last of the world wiring: they need the WaveDirector already holding
	# the build grid and the tower, which is the line above. WorldGen built the
	# camps themselves. Garrisons are host-only — see below.
	for node in get_tree().get_nodes_in_group("camps"):
		node.setup(wave_director)
		node.cleared.connect(_on_camp_cleared.bind(node))
	# Harvests announce themselves; the game routes them to the shared pool
	# (signals up, calls down). The signal only fires on the host.
	for node in get_tree().get_nodes_in_group("resource_nodes"):
		node.harvested.connect(_on_resource_harvested)
	world_ready = true

	if multiplayer.is_server():
		# Our own roster entry was written by host_game(), so no wait here.
		_spawn_player(1)
		# Camp garrisons: host-only, and only safe to post now. Until
		# host_game() assigned a peer, `multiplayer.is_server()` answered TRUE
		# on a joining client too, so a self-guarded version had every client
		# spawning its own guards into a spawner it does not own.
		for node in get_tree().get_nodes_in_group("camps"):
			node.host_post_garrison()
	else:
		# Tell the host we can be spawned into. Until this lands it holds our
		# character (and every state snapshot that goes with it) back.
		hud.show_connecting(false)
		_request_spawn.rpc_id(1)


# Received by a joiner the moment it connects: the host's map, as one number.
# The game root's authority is the server, so plain "authority" mode is right
# here (unlike player nodes — see GOTCHAS).
@rpc("authority", "reliable")
func _receive_world_seed(seed_value: int) -> void:
	if world_ready:
		return
	_begin_world(seed_value)


# Host only: a client has finished building the world and can now be sent
# things that live in it.
@rpc("any_peer", "reliable")
func _request_spawn() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _pending_spawns.has(peer_id):
		return
	_pending_spawns[peer_id]["world"] = true
	_try_spawn_pending(peer_id)


# Host only. Vets the join, then puts the peer on the pending list rather than
# spawning it: `peer_connected` fires when the transport connects, which is
# strictly before the joiner's own _register_player RPC arrives, so at this
# moment we do not yet know their name or their CLASS. Spawning here would
# build every joiner as the fallback class. _on_player_registered finishes the
# job (see the decision log, 2026-08-15).
func _on_peer_connected(peer_id: int) -> void:
	if day_night.phase == DayNightCycle.Phase.NIGHT or run_over:
		# Design rule: joining is day-phase only. Refusing at the app layer
		# is deliberate — ENet's refuse_new_connections flag half-works and
		# leaves the client in limbo instead (see GOTCHAS). Tell them why
		# first; the client leaves itself, and the delayed kick only catches
		# one that never got the message.
		var reason := "The run has already ended." if run_over \
				else "The gates are barred during night assaults — try again at dawn."
		print("[Game] Refused join from peer %d (%s)" % [peer_id, reason])
		_receive_join_refusal.rpc_id(peer_id, reason)
		_kick_after_grace(peer_id)
		return
	_pending_spawns[peer_id] = {"registered": false, "world": false}
	# First thing a joiner gets: this run's map. It has a game scene loaded but
	# deliberately no world in it until this arrives.
	_receive_world_seed.rpc_id(peer_id, world_gen.world_seed)


# Host only: the joiner's class is now in the roster. That is one of the two
# things we wait for — see `_pending_spawns`.
func _on_player_registered(peer_id: int) -> void:
	if not _pending_spawns.has(peer_id):
		return
	_pending_spawns[peer_id]["registered"] = true
	_try_spawn_pending(peer_id)


# Host only: build the joiner's character and push the state that synchronizers
# do not cover, once they are registered AND holding a copy of the world. A
# refused peer never made the pending list, and one that dropped mid-handshake
# was taken off it.
func _try_spawn_pending(peer_id: int) -> void:
	var pending: Dictionary = _pending_spawns.get(peer_id, {})
	if not pending.get("registered", false) or not pending.get("world", false):
		return
	_pending_spawns.erase(peer_id)
	_spawn_player(peer_id)
	team_materials.host_send_snapshot(peer_id)
	glow_tower.host_send_snapshot(peer_id)
	for node in get_tree().get_nodes_in_group("resource_nodes"):
		node.host_send_snapshot(peer_id)
	for node in get_tree().get_nodes_in_group("enemies"):
		node.host_send_snapshot(peer_id)
	# Camps: the guards themselves replicate through the enemy spawner, but the
	# tally that locks each cache is Camp's own state and has to be sent.
	for node in get_tree().get_nodes_in_group("camps"):
		node.host_send_snapshot(peer_id)
	for node in get_tree().get_nodes_in_group("players"):
		node.host_send_snapshot(peer_id)
	# Buildings are replayed by their spawner, but the damage they have taken
	# since is not in the spawn data — a joiner would otherwise see a battered
	# wall at full health and watch it vanish a second later.
	for building in build_manager.all_buildings():
		building.host_send_snapshot(peer_id)
	# Deployables outlive the moment they were cast by a long way, so a joiner
	# who arrives mid-day would otherwise walk over an invisible trap.
	for node in get_tree().get_nodes_in_group("deployables"):
		node.host_replay_to(peer_id)


# Received by a refused joiner: bounce to the menu with the real reason
# before the host's backstop kick turns it into "the host ended the game".
# The game root's authority is the server, so plain "authority" mode is right
# here (unlike player nodes — see GOTCHAS).
@rpc("authority", "reliable")
func _receive_join_refusal(reason: String) -> void:
	_return_to_menu(reason)


# Host only: the backstop kick behind the refusal RPC. A child Timer (not a
# SceneTreeTimer) so it can never fire after the scene is gone.
func _kick_after_grace(peer_id: int) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = refusal_kick_delay
	timer.timeout.connect(func() -> void:
		if peer_id in multiplayer.get_peers():
			(multiplayer as SceneMultiplayer).disconnect_peer(peer_id)
		timer.queue_free())
	add_child(timer)
	timer.start()


# Host only (WaveDirector emits at dawn on the host).
func _on_night_survived(night: int) -> void:
	if run_over:
		return
	# One chest per player; contents go into the shared pool for now.
	var chests := Network.player_count()
	team_materials.host_add(&"wood", chest_wood * chests)
	team_materials.host_add(&"stone", chest_stone * chests)
	team_materials.host_add(&"essence_faint", chest_essence * chests)
	print("[Game] Night %d survived - %d chest(s) opened" % [night, chests])
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
	print("[Game] Run ended: %s after night %d (+%d XP)"
			% ["VICTORY" if victory else "DEFEAT", nights, xp])


func _on_resource_harvested(material_type: MaterialType, count: int) -> void:
	team_materials.host_add(material_type.id, count)


# Host only. The cache unlocks itself (Camp pushes the tally); this is the run's
# record that a site fell, which is the thing worth reading back in a log.
func _on_camp_cleared(camp: Camp) -> void:
	# Stamped here rather than inside Camp because the day number lives on this
	# scene's cycle; Regrowth measures the site's repopulate delay against it.
	camp.cleared_on_day = day_night.day_number
	print("[Camp] %s at %v cleared on day %d - %s waiting in the cache"
			% [camp.type.id, camp.global_position, day_night.day_number,
			Materials.cost_text(camp.type.loot)])


func _on_peer_disconnected(peer_id: int) -> void:
	# Dropped before registering (or refused and kicked): nothing was ever
	# spawned, but the pending entry would outlive them.
	_pending_spawns.erase(peer_id)
	if players.has_node(str(peer_id)):
		# Freeing on the host makes the MultiplayerSpawner despawn it everywhere.
		players.get_node(str(peer_id)).queue_free()


# Host only: pick spawn data and tell the spawner to build it everywhere.
func _spawn_player(peer_id: int) -> void:
	var angle := players.get_child_count() * TAU / float(Network.MAX_PLAYERS)
	player_spawner.spawn({
		"peer_id": peer_id,
		"position": Vector3(spawn_radius, 0, 0).rotated(Vector3.UP, angle),
		# The owner's chosen class, read from the roster the host now knows is
		# populated (_on_player_registered guarantees it).
		"class_id": Network.players[peer_id].get("class_id", Classes.ALL[0].id),
	})


# Runs on every peer when the spawner (re)creates a player.
func _build_player(data: Dictionary) -> Node:
	var player := PlayerScene.instantiate() as Player
	# The node name doubles as the owner's peer id (see player.gd).
	player.name = str(data.peer_id)
	player.position = data.position
	# Set before add_child so _ready() sees the right sprite and max_hp —
	# the whole reason this spawner uses an explicit spawn_function.
	player.class_type = Classes.by_id(data.class_id)
	if _spawn_at_override != Vector3.ZERO and data.peer_id == multiplayer.get_unique_id():
		# Dev cheat (--spawn-at): only the owner overrides — position is
		# client-authority, so the synchronizer pushes it to everyone else.
		player.position = _spawn_at_override
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
	print("[Game] Returning to menu: %s" % reason)
	Network.last_error = reason
	_leave_run_for(MAIN_MENU_SCENE)


# Leaving the run, whatever the destination. The peer is always released first:
# a scene change does not close a connection, and a lingering one would hold the
# port against the next host attempt.
func _leave_run_for(scene_path: String) -> void:
	Network.leave_game()
	get_tree().change_scene_to_file(scene_path)


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
		elif arg.begins_with("--spawn-at="):
			# Dev cheat: start the local player at cell x,z (e.g. --spawn-at=30,0)
			# — playtest distance-based things (glow edge, roamers) without the walk.
			_spawn_at_override = Vector3(
					float(arg.get_slice("=", 1).get_slice(",", 0)), 0.0,
					float(arg.get_slice("=", 1).get_slice(",", 1)))
		elif arg == "--auto-harvest":
			_start_auto_harvest()
		elif arg == "--auto-build":
			_run_auto_build()
		elif arg == "--auto-block-test":
			_run_auto_block_test()
		elif arg == "--auto-siege":
			_run_auto_siege()
		elif arg.begins_with("--strip-nodes="):
			_run_strip_nodes(int(arg.get_slice("=", 1)))
		elif arg == "--auto-fight":
			_start_auto_fight()
		elif arg == "--auto-camp":
			_start_auto_camp()
		elif arg == "--auto-camp-clear":
			_start_auto_camp_clear()
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
		elif arg.begins_with("--world-seed="):
			# Dev: reproduce one particular map (a run rolls a fresh seed). Host
			# only — a client takes whatever the host sends and ignores this.
			_seed_override = int(arg.get_slice("=", 1))
		elif arg.begins_with("--final-day="):
			# Dev helper: shorter runs, e.g. --final-day=1 to win after night 1.
			day_night.final_day = int(arg.get_slice("=", 1))
		elif arg.begins_with("--log-players-after-sec="):
			for stamp in arg.get_slice("=", 1).split(","):
				_log_players_after(float(stamp))
		elif arg.begins_with("--log-crowding-after-sec="):
			for stamp in arg.get_slice("=", 1).split(","):
				_log_crowding_after(float(stamp))


# Smoke-test hook (godot -- --auto-fight): stand on the eastern approach lane
# and cast the whole kit at the nearest monster. Exercises aim/cast RPCs and
# every ability kind the chosen class happens to carry. Distances in cells.
func _start_auto_fight() -> void:
	var timer := Timer.new()
	timer.wait_time = 0.6
	timer.autostart = true
	timer.timeout.connect(_auto_fight_tick)
	add_child(timer)


func _auto_fight_tick() -> void:
	var me: Player = players.get_node_or_null(str(multiplayer.get_unique_id()))
	if me == null or not me.is_multiplayer_authority():
		return
	# Stand ON the first approach lane, a few cells out from the heart. Asked of
	# the pathfinder rather than hardcoded: openings are rolled per run now, and
	# a rock can make A* detour a row even on the lane it was handed.
	if world_gen.opening_positions.is_empty():
		return
	var lane := build_manager.path_to_heart(world_gen.opening_positions[0])
	var stand := Vector3(3.125, 0.0, 0.5)
	for point in lane:
		if Vector2(point).length() < 4.0:
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
	# Cast the first thing that is both off cooldown and actually in reach.
	# Reach comes from each ability's own data, so a melee kit swings when they
	# arrive instead of whiffing at the range a bow would have fired from.
	for ability in [me.class_type.ability_2, me.class_type.ability_1,
			me.class_type.basic_attack]:
		if ability == null or me.cooldown_remaining(ability) > 0.0:
			continue
		if distance <= _auto_fight_reach(ability):
			me.try_cast_toward(ability, direction)
			return


# Cells within which the harness considers an ability worth casting.
func _auto_fight_reach(ability: AbilityType) -> float:
	match ability.kind:
		AbilityType.Kind.PROJECTILE:
			return ability.projectile_range / PX_PER_UNIT
		AbilityType.Kind.MELEE_ARC:
			return ability.melee_range / PX_PER_UNIT
		AbilityType.Kind.DEPLOYABLE:
			# Drop it while they are still walking in, so the root gets tested.
			return AUTO_FIGHT_DEPLOY_RANGE
		AbilityType.Kind.SELF_BUFF:
			# Pop it as they close, which is when it would matter.
			return AUTO_FIGHT_BUFF_RANGE
	return 0.0


# Smoke-test hook (godot -- --auto-camp): stand at the nearest camp's cache and
# try to loot it every 2 s. While the garrison stands the host must REFUSE (the
# [ResourceNode] refusal log); once something has cleared the camp the same call
# must pay out (the [Loot] log). Deliberately runs on host or client — pointing
# it at a client is how the two-instance smoke proves a client-initiated loot
# travels the whole RPC chain.
func _start_auto_camp() -> void:
	var timer := Timer.new()
	timer.wait_time = 2.0
	timer.autostart = true
	timer.timeout.connect(_auto_camp_tick)
	add_child(timer)


func _auto_camp_tick() -> void:
	var me: Player = players.get_node_or_null(str(multiplayer.get_unique_id()))
	if me == null or not me.is_multiplayer_authority():
		return
	# Nearest camp to the village that still has loot in it.
	var target: Camp = null
	var best := INF
	for node in get_tree().get_nodes_in_group("camps"):
		var camp := node as Camp
		var cache := camp.get_node_or_null("Cache") as LootCache
		if cache == null or cache.amount <= 0:
			continue
		var dist: float = camp.global_position.length_squared()
		if dist < best:
			best = dist
			target = camp
	if target == null:
		return
	var cache := target.get_node_or_null("Cache") as LootCache
	var stand := cache.global_position + Vector3(1.0, 0.0, 0.0)
	if me.global_position.distance_to(stand) > 0.1:
		# Arrive this tick, ask next tick: a freshly moved Area3D reports no
		# overlaps until it has been through a physics step, so harvesting on the
		# same tick as the teleport silently finds nothing (see GOTCHAS).
		me.global_position = stand
		print("[Camp] auto-camp: arrived at %s, %d guards left" % [
				target.type.id, target.guards_remaining])
		return
	print("[Camp] auto-camp: trying %s, %d guards left" % [
			target.type.id, target.guards_remaining])
	me.try_harvest()


# Smoke-test hook (godot -- --auto-camp-clear): host cheat that kills every camp
# garrison in the world once, so the unlock -> loot half of --auto-camp can be
# exercised without a real fight. Kills rather than despawns, so it goes through
# the same `died` signal a player's arrow would.
func _start_auto_camp_clear() -> void:
	# Late enough that --auto-camp on a client gets several *refused* attempts in
	# first: the lock is half of what this pair of hooks exists to prove.
	await get_tree().create_timer(12.0).timeout
	if not multiplayer.is_server():
		return
	var killed := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.behavior != Enemy.Behavior.GUARD or enemy.hp <= 0:
			continue
		enemy.host_take_damage(enemy.hp)
		killed += 1
	print("[Camp] auto-camp-clear: put down %d guards" % killed)


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
	await get_tree().create_timer(1.0).timeout
	# Towers upgrade walls in place: this wall becomes a sentry, and the wall's
	# refund comes off the sentry's cost.
	build_manager.request_place.rpc_id(1, &"wall", Vector2i(4, 3))
	await get_tree().create_timer(1.0).timeout
	build_manager.request_place.rpc_id(1, &"sentry_tower", Vector2i(4, 3))
	await get_tree().create_timer(1.0).timeout
	# ...but the swap only goes one way: a wall may not replace a tower.
	build_manager.request_place.rpc_id(1, &"wall", Vector2i(4, 3))
	await get_tree().create_timer(1.0).timeout
	# Tier upgrades: clicking the sentry's own hotbar slot on the sentry that is
	# already standing walks it up its line, one tier per click. The third click
	# must be refused — sentry_tower_iii is the end of the chain. (Needs the
	# essence grant; the smoke command passes it.)
	build_manager.request_place.rpc_id(1, &"sentry_tower", Vector2i(4, 3))
	await get_tree().create_timer(1.0).timeout
	build_manager.request_place.rpc_id(1, &"sentry_tower", Vector2i(4, 3))
	await get_tree().create_timer(1.0).timeout
	build_manager.request_place.rpc_id(1, &"sentry_tower", Vector2i(4, 3))
	await get_tree().create_timer(1.0).timeout
	# The class gate, both halves, for whatever class this run picked: your own
	# exclusive must place and somebody else's must be refused. Derived from the
	# data rather than naming a building, so it keeps testing the rule as
	# classes are added.
	var mine: BuildingType = null
	var theirs: BuildingType = null
	for type in build_manager.buildable_types:
		# Tiers carry their line's class_id too — skip them, or this picks a
		# top tier nobody can place from scratch.
		if type.class_id == &"" or not type.placeable:
			continue
		if type.class_id == Network.local_player_class:
			mine = type
		elif theirs == null:
			theirs = type
	if mine != null:
		build_manager.request_place.rpc_id(1, mine.id, Vector2i(2, 3))
		await get_tree().create_timer(1.0).timeout
	if theirs != null:
		build_manager.request_place.rpc_id(1, theirs.id, Vector2i(2, 4))
		await get_tree().create_timer(1.0).timeout
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


# Smoke-test hook (godot -- --auto-siege): ring the tower's heart with walls,
# leaving exactly one cell open. That is a legal maze — the never-block rule
# only requires *a* path — but it is a preposterous one, so the horde must stop
# walking it and break in instead. Assert on "[Building] wall ... was
# destroyed": no such line means the breach rule never fired. Pair it with
# --grant-materials (the ring costs about 50 wood) and a long night.
func _run_auto_siege() -> void:
	await get_tree().create_timer(3.0).timeout
	var radius := 3
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			if maxi(absi(x), absi(z)) != radius:
				continue
			# The gap. Left on the south side, away from the tower's own
			# footprint, so the ring is legal however the openings fell.
			if x == 0 and z == radius:
				continue
			build_manager.request_place.rpc_id(1, &"wall", Vector2i(x, z))
			await get_tree().process_frame
	print("[Game] auto-siege: the heart is ringed, one cell left open")


# Smoke-test hook (godot -- --strip-nodes=N): host cheat that fells N resource
# nodes outright, so a run can reach the picked-over state Regrowth exists for
# without spending twenty real minutes harvesting to get there. Goes through the
# ordinary payout so the pool and the build grid both see it exactly as they
# would a player's last chop.
func _run_strip_nodes(count: int) -> void:
	await get_tree().create_timer(2.0).timeout
	if not multiplayer.is_server():
		return
	var stripped := 0
	for node in get_tree().get_nodes_in_group("resource_nodes"):
		if stripped >= count:
			break
		var resource := node as ResourceNode
		if resource == null or resource is LootCache or resource.amount <= 0:
			continue
		resource.host_fell()
		stripped += 1
	print("[Game] strip-nodes: felled %d node(s)" % stripped)


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
		# A locked loot cache is a resource node that would refuse us — the
		# harness would park on it forever. --auto-camp is the hook for those.
		if node.amount <= 0 or node.harvest_block_reason() != "":
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
		print("[Game] t=%d player %s at %v" % [int(delay_sec), player.name, player.position])


# Dev hook: report how tightly the monsters are packed, so a headless run can
# assert that separation steering is doing something. The number that matters is
# the closest pair — stacking shows up there long before it shows up in an
# average, because a stack IS a pair at distance zero.
func _log_crowding_after(delay_sec: float) -> void:
	await get_tree().create_timer(delay_sec).timeout
	var living: Array[Node] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.hp > 0:
			living.append(node)
	var closest := INF
	var closest_pair := "none"
	var overlapping := 0
	for i in living.size():
		for j in range(i + 1, living.size()):
			var dist: float = living[i].global_position.distance_to(living[j].global_position)
			if dist < 0.4:
				overlapping += 1
			if dist < closest:
				closest = dist
				closest_pair = "%s(%d)/%s(%d)" % [
						living[i].name, living[i].behavior,
						living[j].name, living[j].behavior]
	print("[Game] t=%d crowding: %d alive, %d pair(s) closer than 0.4, closest %.2f (%s)" % [
			int(delay_sec), living.size(), overlapping,
			0.0 if closest == INF else closest, closest_pair])


func _save_screenshot_after(delay_sec: float) -> void:
	await get_tree().create_timer(delay_sec).timeout
	# Wait for a full frame first (docs: tutorials/rendering/viewports.rst) —
	# without it the capture can be a STALE frame (seen on macOS/Metal).
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "user://game_shot_%d.png" % int(delay_sec)
	image.save_png(path)
	print("[Game] Screenshot saved to %s (%d fps)" % [
			ProjectSettings.globalize_path(path), Engine.get_frames_per_second()])
