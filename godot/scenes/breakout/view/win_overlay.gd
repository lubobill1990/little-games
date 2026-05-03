extends CanvasLayer
## Win overlay — used both for level-complete (advance to next level) and
## pack-complete (after the final level). Two modes via `set_mode()`.

signal next_level_requested()
signal restart_requested()
signal menu_requested()

enum Mode { LEVEL_CLEAR = 0, PACK_COMPLETE = 1 }

var _title_label: Label
var _score_label: Label
var _primary_btn: Button
var _replay_btn: Button
var _quit_btn: Button
var _mode: int = Mode.LEVEL_CLEAR


func _ready() -> void:
	layer = 11
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.add_theme_constant_override("separation", 16)
	add_child(vbox)
	_title_label = Label.new()
	_title_label.text = "LEVEL CLEAR"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 48)
	vbox.add_child(_title_label)
	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_score_label)
	_primary_btn = Button.new()
	_primary_btn.text = "Next level"
	_primary_btn.pressed.connect(_on_primary)
	vbox.add_child(_primary_btn)
	_replay_btn = Button.new()
	_replay_btn.text = "Replay pack"
	_replay_btn.pressed.connect(func() -> void: restart_requested.emit())
	_replay_btn.visible = false
	vbox.add_child(_replay_btn)
	_quit_btn = Button.new()
	_quit_btn.text = "Quit to menu"
	_quit_btn.pressed.connect(func() -> void: menu_requested.emit())
	vbox.add_child(_quit_btn)
	visibility_changed.connect(_on_visibility_changed)
	InputManager.action_pressed.connect(_on_action_pressed)
	visible = false


## Configure the overlay before show_with(). LEVEL_CLEAR shows a "Next level"
## button; PACK_COMPLETE swaps in "Replay pack" + retitles.
func set_mode(mode: int) -> void:
	_mode = mode
	if _mode == Mode.PACK_COMPLETE:
		_title_label.text = "PACK COMPLETE"
		_primary_btn.text = "Replay pack"
		# Reuse the primary button as replay-pack to keep the layout simple.
		_replay_btn.visible = false
	else:
		_title_label.text = "LEVEL CLEAR"
		_primary_btn.text = "Next level"
		_replay_btn.visible = false


func show_with(score: int) -> void:
	if _mode == Mode.PACK_COMPLETE:
		_score_label.text = "Run score: %d — more levels coming" % score
	else:
		_score_label.text = "Score: %d" % score
	visible = true


func _on_visibility_changed() -> void:
	if visible and is_instance_valid(_primary_btn):
		_primary_btn.grab_focus()


func _on_primary() -> void:
	if _mode == Mode.PACK_COMPLETE:
		# Replay pack from level 1.
		restart_requested.emit()
	else:
		next_level_requested.emit()


func _on_action_pressed(action: StringName) -> void:
	if not visible:
		return
	if action == &"ui_accept":
		_on_primary()
	elif action == &"ui_cancel":
		menu_requested.emit()
