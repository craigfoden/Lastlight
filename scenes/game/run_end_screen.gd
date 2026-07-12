class_name RunEndScreen
extends CanvasLayer
## Full-screen curtain shown when the run ends, on every peer: outcome,
## nights survived, and the run XP that session 4's profile will bank.

signal menu_requested

@onready var _title: Label = %TitleLabel
@onready var _stats: Label = %StatsLabel


func _ready() -> void:
	visible = false
	%MenuButton.pressed.connect(menu_requested.emit)


func show_results(victory: bool, nights: int, xp: int) -> void:
	visible = true
	if victory:
		_title.text = "DAWN OF THE SEVENTH DAY"
		_stats.text = "The village stands. The darkness recedes.\n\nNights survived: %d\nRun XP: %d" % [nights, xp]
	else:
		_title.text = "THE NECROMANCER DESCENDS"
		_stats.text = "The last light is extinguished.\n\nNights survived: %d\nRun XP: %d" % [nights - 1, xp]
