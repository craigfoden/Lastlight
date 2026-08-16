extends Control
## Talent screen: spend the points a class has earned. Reached from the main
## menu, and the only thing in the game that calls `Profile.unlock_talent()` —
## points have accrued since session 4 with nothing to spend them on.
##
## Deliberately out of the run rather than in it. Talents are read once, on
## spawn (player.gd), and every one of them scales a number the owning peer
## simulates alone; letting them change mid-run would mean either re-reading
## them live or syncing them, and neither is worth it for a meta screen.
##
## The rows are built from `Talents.for_class()` at runtime, so a new talent is
## still a .tres and a preload — nothing here knows any talent by name.

const MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"

var _class_type: ClassType

@onready var _class_tabs: HBoxContainer = %ClassTabs
@onready var _summary: Label = %Summary
@onready var _rows: VBoxContainer = %Rows


func _ready() -> void:
	for class_type in Classes.ALL:
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(130, 0)
		button.text = class_type.display_name
		button.pressed.connect(_show_class.bind(class_type))
		_class_tabs.add_child(button)
	%BackButton.pressed.connect(_go_back)
	# Open on the class you last played — the one whose points just changed.
	_show_class(Classes.by_id(Network.local_player_class))


func _show_class(class_type: ClassType) -> void:
	_class_type = class_type
	for i in _class_tabs.get_child_count():
		var button := _class_tabs.get_child(i) as Button
		button.set_pressed_no_signal(Classes.ALL[i] == class_type)
	_refresh()


# Rebuilt rather than updated in place: the screen is a handful of rows behind a
# button press, and a rebuild cannot leave a stale "Unlock" on a talent that was
# just bought.
func _refresh() -> void:
	var class_id := _class_type.id
	var points := Profile.talent_points(class_id)
	var xp := int(Profile.class_xp.get(String(class_id), 0))
	_summary.text = "%s — level %d (%d XP) · %d point%s to spend" % [
			_class_type.display_name, Profile.class_level(class_id), xp,
			points, "" if points == 1 else "s"]

	for child in _rows.get_children():
		child.queue_free()

	var talents := Talents.for_class(class_id)
	if talents.is_empty():
		_rows.add_child(_note("No talents written for this class yet."))
		return
	var owned := Profile.talents_for(class_id)
	for talent in talents:
		_rows.add_child(_row_for(talent, String(talent.id) in owned, points))
	if points <= 0 and owned.size() < talents.size():
		# Survive a night to earn the next one — say so, rather than leaving a
		# column of dead buttons explaining nothing.
		_rows.add_child(_note("Class levels come from run XP. Survive more nights."))


func _row_for(talent: TalentType, owned: bool, points: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)

	var text := Label.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.text = "%s\n%s" % [talent.display_name, talent.description]
	if owned:
		text.modulate = Color(0.65, 0.9, 0.65)
	elif points <= 0:
		text.modulate = Color(1, 1, 1, 0.5)
	row.add_child(text)

	var button := Button.new()
	button.custom_minimum_size = Vector2(110, 0)
	button.text = "Learned" if owned else "Unlock"
	button.disabled = owned or points <= 0
	if not owned:
		button.pressed.connect(_unlock.bind(talent))
	row.add_child(button)
	return row


func _note(message: String) -> Label:
	var label := Label.new()
	label.modulate = Color(1, 1, 1, 0.5)
	label.text = message
	return label


func _unlock(talent: TalentType) -> void:
	# Profile owns the rule (points available, not already owned) and saves;
	# this screen only asks and redraws whatever the answer was.
	if Profile.unlock_talent(talent):
		print("[Menu] Learned %s" % talent.id)
	_refresh()


func _go_back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
