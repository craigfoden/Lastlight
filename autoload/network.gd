extends Node
## Autoload "Network": connection lifecycle and the roster of connected players.
##
## Host-authoritative model: the hosting player's peer id is always 1 and their
## instance is the source of truth for game state. Clients only ever *request*
## changes; the host validates and broadcasts results (see docs/ARCHITECTURE.md).
##
## Transport is ENet during development. For release we swap in GodotSteam's
## SteamMultiplayerPeer behind this same interface — nothing outside this file
## should care which peer implementation is active.

signal player_list_changed
signal connection_failed
signal server_ended

enum StartMode { NONE, HOST, JOIN }

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 4

## What the game scene should do once it finishes loading. Set by the main
## menu; the game scene connects *after* it is in the tree so replication
## packets never race the scene load.
var start_mode := StartMode.NONE
var pending_address := "127.0.0.1"

## Set by the main menu before hosting/joining.
var local_player_name := "Player"

## Shown on the menu after being bounced back there (failed join, host quit).
var last_error := ""

## peer_id -> { "name": String }. Every peer keeps an identical copy.
var players := {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game(port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	# The host occupies one player slot, so allow one fewer connection.
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players = {1: {"name": local_player_name}}
	player_list_changed.emit()
	print("[Network] Hosting on port %d as '%s'" % [port, local_player_name])
	return OK


func join_game(address: String, port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	print("[Network] Joining %s:%d as '%s'..." % [address, port, local_player_name])
	return OK


func leave_game() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	start_mode = StartMode.NONE
	player_list_changed.emit()


func player_count() -> int:
	return players.size()


# When someone joins, every existing peer introduces itself directly to the
# newcomer, so the newcomer assembles the full roster from those messages.
func _on_peer_connected(id: int) -> void:
	_register_player.rpc_id(id, local_player_name)


@rpc("any_peer", "reliable")
func _register_player(player_name: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	players[sender] = {"name": player_name}
	player_list_changed.emit()
	print("[Network] Player joined: '%s' (peer %d)" % [player_name, sender])


func _on_peer_disconnected(id: int) -> void:
	var info: Dictionary = players.get(id, {})
	players.erase(id)
	player_list_changed.emit()
	print("[Network] Player left: '%s' (peer %d)" % [info.get("name", "?"), id])


func _on_connected_to_server() -> void:
	players[multiplayer.get_unique_id()] = {"name": local_player_name}
	player_list_changed.emit()
	print("[Network] Connected to host.")


func _on_connection_failed() -> void:
	leave_game()
	connection_failed.emit()
	print("[Network] Connection failed.")


func _on_server_disconnected() -> void:
	leave_game()
	server_ended.emit()
	print("[Network] Host disconnected.")
