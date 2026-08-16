class_name RunEndScreen
extends CanvasLayer
## Full-screen curtain shown when the run ends, on every peer: outcome,
## nights survived, and the run XP that session 4's profile will bank.

signal menu_requested

## The point in the game where you have just been *told* you earned talent
## points is the point where you want to spend them, and until session 18 the
## only way there was to leave, land on the menu, and find the button. Both
## exits leave the run the same way (the game scene has to be torn down and the
## peer released either way) — this one just lands somewhere more useful.
signal talents_requested

@onready var _title: Label = %TitleLabel
@onready var _stats: Label = %StatsLabel
@onready var _talents_button: Button = %TalentsButton


func _ready() -> void:
	visible = false
	%MenuButton.pressed.connect(menu_requested.emit)
	_talents_button.pressed.connect(talents_requested.emit)


func show_results(victory: bool, nights: int, xp: int) -> void:
	visible = true
	var class_id := Network.local_player_class
	# Offered only when there is actually something to spend — a button that
	# takes you to an empty screen is worse than no button.
	_talents_button.visible = Profile.talent_points(class_id) > 0
	var progress := "Account level %d - %s level %d (%d talent point(s) free)" % [
		Profile.account_level(),
		String(class_id).capitalize(),
		Profile.class_level(class_id),
		Profile.talent_points(class_id),
	]
	if victory:
		_title.text = "DAWN OF THE SEVENTH DAY"
		_stats.text = "The village stands. The darkness recedes.\n\nNights survived: %d\nRun XP banked: %d\n%s" % [nights, xp, progress]
	else:
		_title.text = "THE NECROMANCER DESCENDS"
		_stats.text = "The last light is extinguished.\n\nNights survived: %d\nRun XP banked: %d\n%s" % [nights - 1, xp, progress]
