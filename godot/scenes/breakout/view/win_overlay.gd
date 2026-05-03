extends CanvasLayer
## Win overlay — fires when all destructible bricks are cleared.
## ui_accept = retry (fresh game); ui_cancel = quit to menu.

signal restart_requested()
signal menu_requested()

var _score_label: Label
var _retry_btn: Button

func _ready() -> void:
	layer = 11   # Above game-over so a simultaneous transition is visible.
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
	var title := Label.new()
	title.text = "YOU WIN!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)
	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_score_label)
	_retry_btn = Button.new()
	_retry_btn.text = "Retry"
	_retry_btn.pressed.connect(func() -> void: restart_requested.emit())
	vbox.add_child(_retry_btn)
	var quit_btn := Button.new()
	quit_btn.text = "Quit to menu"
	quit_btn.pressed.connect(func() -> void: menu_requested.emit())
	vbox.add_child(quit_btn)
	visibility_changed.connect(_on_visibility_changed)
	InputManager.action_pressed.connect(_on_action_pressed)
	visible = false

func show_with(score: int) -> void:
	_score_label.text = "Score: %d" % score
	visible = true

func _on_visibility_changed() -> void:
	if visible and is_instance_valid(_retry_btn):
		_retry_btn.grab_focus()

func _on_action_pressed(action: StringName) -> void:
	if not visible:
		return
	if action == &"ui_accept":
		restart_requested.emit()
	elif action == &"ui_cancel":
		menu_requested.emit()
