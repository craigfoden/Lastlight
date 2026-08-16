extends Control
## Title screen: pick a name, then host a game or join one by IP — or step into
## the talent screen to spend what earlier runs banked.
##
## Scripted startup for automated testing (args go after `--` on the command line):
##   godot -- --host             host immediately
##   godot -- --join=127.0.0.1   join immediately
##   godot -- --name=Craig       set the player name
##   godot -- --class=paladin    pick a class without the select screen
##
## A human goes menu -> class select -> game. A scripted run skips the select
## screen entirely (it would sit there waiting for a click that never comes)
## and takes its class from `--class=`, defaulting to the first class.

const GAME_SCENE := "res://scenes/game/game.tscn"
const CLASS_SELECT_SCENE := "res://scenes/class_select/class_select.tscn"
const TALENT_SCREEN_SCENE := "res://scenes/talents/talent_screen.tscn"

## Cmdline autostart must run once per launch, not every time we come back to
## the menu — otherwise a failed scripted --join retries in a loop forever.
static var _cmdline_applied := false

@onready var name_edit: LineEdit = %NameEdit
@onready var address_edit: LineEdit = %AddressEdit
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	%HostButton.pressed.connect(_start_host)
	%JoinButton.pressed.connect(_start_join)
	# Talents are spent between runs, not during one — the character reads them
	# once on spawn (see player.gd), so the menu is where they belong.
	%TalentsButton.pressed.connect(
			get_tree().change_scene_to_file.bind(TALENT_SCREEN_SCENE))
	# `quit()` rather than closing the window: it runs the same shutdown path the
	# window's close button does, so autoloads still get their notifications and
	# the profile is written out.
	%QuitButton.pressed.connect(get_tree().quit)
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
		elif arg.begins_with("--class="):
			var wanted := StringName(arg.get_slice("=", 1))
			if Classes.has_id(wanted):
				Network.local_player_class = wanted
			else:
				push_error("--class=%s is not a known class; staying as %s."
						% [wanted, Network.local_player_class])
		elif arg.begins_with("--quit-after-sec="):
			# For scripted smoke tests: headless frames run uncapped, so
			# --quit-after (frames) is useless for timing — quit on wall clock.
			# The SceneTreeTimer keeps running across the scene change.
			var seconds := arg.get_slice("=", 1).to_float()
			get_tree().create_timer(seconds).timeout.connect(get_tree().quit)
	for arg in args:
		if arg == "--host":
			_start_host(true)
			return
		if arg.begins_with("--join"):
			if arg.begins_with("--join="):
				address_edit.text = arg.get_slice("=", 1)
			_start_join(true)
			return


func _start_host(scripted := false) -> void:
	_store_player_name()
	Network.start_mode = Network.StartMode.HOST
	_leave_menu(scripted)


func _start_join(scripted := false) -> void:
	_store_player_name()
	Network.start_mode = Network.StartMode.JOIN
	Network.pending_address = address_edit.text.strip_edges()
	_leave_menu(scripted)


# A human picks a class first; a scripted run already has one from --class=
# and must not stall on a screen waiting for a click.
func _leave_menu(scripted: bool) -> void:
	get_tree().change_scene_to_file(GAME_SCENE if scripted else CLASS_SELECT_SCENE)


func _store_player_name() -> void:
	var chosen := name_edit.text.strip_edges()
	Network.local_player_name = chosen if chosen != "" else "Player"
