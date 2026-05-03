extends Control
## Touch-only on-screen FIRE button. Anchored bottom-right. Emits
## `fire_requested` on tap-down. Calls `accept_event()` so the touch is not
## also consumed by the parent's drag-zone tracker.
##
## On non-touch builds this is harmless: kbd / gamepad still routes `fire`
## via the normal InputManager path.

signal fire_requested()

const SIZE_PX: float = 80.0
const MARGIN_PX: float = 24.0

var _bg: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(SIZE_PX, SIZE_PX)
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -SIZE_PX - MARGIN_PX
	offset_top = -SIZE_PX - MARGIN_PX
	offset_right = -MARGIN_PX
	offset_bottom = -MARGIN_PX
	_bg = ColorRect.new()
	_bg.color = Color(1.0, 0.3, 0.3, 0.35)
	_bg.anchor_right = 1.0
	_bg.anchor_bottom = 1.0
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	var label := Label.new()
	label.text = "FIRE"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			fire_requested.emit()
			accept_event()
	elif event is InputEventMouseButton:
		var m: InputEventMouseButton = event
		if m.pressed and m.button_index == MOUSE_BUTTON_LEFT:
			fire_requested.emit()
			accept_event()
