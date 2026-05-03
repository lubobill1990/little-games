extends CanvasLayer
## Game-over overlay. Layer 10. ui_accept retries; ui_cancel returns to menu.

signal restart_requested()
signal menu_requested()

var _score_label: Label
var _menu_btn: Button

func _ready() -> void:
	layer = 10
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
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
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)
	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_score_label)
	var hint := Label.new()
	hint.text = "Press Confirm to retry"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	vbox.add_child(hint)
	_menu_btn = Button.new()
	_menu_btn.text = "Back to menu"
	_menu_btn.pressed.connect(func() -> void: menu_requested.emit())
	vbox.add_child(_menu_btn)
	InputManager.action_pressed.connect(_on_action_pressed)
	visible = false

func show_with(score: int) -> void:
	_score_label.text = "Final Score: %d" % score
	visible = true

func _on_action_pressed(action: StringName) -> void:
	if not visible:
		return
	if action == &"ui_accept":
		restart_requested.emit()
	elif action == &"ui_cancel":
		menu_requested.emit()
