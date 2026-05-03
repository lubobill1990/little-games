extends CanvasLayer
## Pause overlay for breakout. Layer 10. Mirrors the snake/2048 pattern.

signal menu_requested()

var _menu_btn: Button

func _ready() -> void:
	layer = 10
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
	var label := Label.new()
	label.text = "PAUSED"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 36)
	vbox.add_child(label)
	var hint := Label.new()
	hint.text = "Press Pause to resume"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	vbox.add_child(hint)
	_menu_btn = Button.new()
	_menu_btn.text = "Back to menu"
	_menu_btn.pressed.connect(func() -> void: menu_requested.emit())
	vbox.add_child(_menu_btn)
	visibility_changed.connect(_on_visibility_changed)
	InputManager.action_pressed.connect(_on_action_pressed)

func _on_visibility_changed() -> void:
	if visible and is_instance_valid(_menu_btn):
		_menu_btn.grab_focus()

func _on_action_pressed(action: StringName) -> void:
	if not visible:
		return
	if action == &"ui_cancel":
		menu_requested.emit()
