extends Control
## Title screen: pick a name, then host a game or join one by IP.
##
## Scripted startup for automated testing (args go after `--` on the command line):
##   godot -- --host             host immediately
##   godot -- --join=127.0.0.1   join immediately
##   godot -- --name=Craig       set the player name

const GAME_SCENE := "res://scenes/game/game.tscn"
## Branch-only (3d-ortho-prototype): the session-8 hybrid look slice. Reached
## by the menu button or `-- --proto3d` so nobody needs to launch the scene
## by path. Remove button + flag if the branch is abandoned.
const PROTO3D_SCENE := "res://scenes/proto3d/proto3d.tscn"

## Cmdline autostart must run once per launch, not every time we come back to
## the menu — otherwise a failed scripted --join retries in a loop forever.
static var _cmdline_applied := false

@onready var name_edit: LineEdit = %NameEdit
@onready var address_edit: LineEdit = %AddressEdit
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	%HostButton.pressed.connect(_start_host)
	%JoinButton.pressed.connect(_start_join)
	%Proto3DButton.pressed.connect(_start_proto3d)
	name_edit.text = "Player %d" % randi_range(1, 99)
	if Network.last_error != "":
		status_label.text = Network.last_error
		Network.last_error = ""
	# Deferred: autostart changes scene, which is not allowed while the tree
	# is still busy adding this one (_ready runs mid-setup).
	_apply_cmdline_args.call_deferred()


func _apply_cmdline_args() -> void:
	if _cmdline_applied:
		return
	_cmdline_applied = true
	var args := OS.get_cmdline_user_args()
	# Name and test helpers first, so they apply before any host/join fires.
	for arg in args:
		if arg.begins_with("--name="):
			name_edit.text = arg.get_slice("=", 1)
		elif arg.begins_with("--quit-after-sec="):
			# For scripted smoke tests: headless frames run uncapped, so
			# --quit-after (frames) is useless for timing — quit on wall clock.
			# The SceneTreeTimer keeps running across the scene change.
			var seconds := arg.get_slice("=", 1).to_float()
			get_tree().create_timer(seconds).timeout.connect(get_tree().quit)
	for arg in args:
		if arg == "--proto3d":
			_start_proto3d()
			return
		if arg == "--host":
			_start_host()
			return
		if arg.begins_with("--join"):
			if arg.begins_with("--join="):
				address_edit.text = arg.get_slice("=", 1)
			_start_join()
			return


func _start_host() -> void:
	_store_player_name()
	Network.start_mode = Network.StartMode.HOST
	get_tree().change_scene_to_file(GAME_SCENE)


func _start_proto3d() -> void:
	get_tree().change_scene_to_file(PROTO3D_SCENE)


func _start_join() -> void:
	_store_player_name()
	Network.start_mode = Network.StartMode.JOIN
	Network.pending_address = address_edit.text.strip_edges()
	get_tree().change_scene_to_file(GAME_SCENE)


func _store_player_name() -> void:
	var chosen := name_edit.text.strip_edges()
	Network.local_player_name = chosen if chosen != "" else "Player"
