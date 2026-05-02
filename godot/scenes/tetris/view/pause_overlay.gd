extends CanvasLayer
## Pause overlay. Layer 10 = above HUD/touch controls. Visible when paused.

func _ready() -> void:
	layer = 10
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	var label := Label.new()
	label.text = "PAUSED\n\nPress Pause to resume"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 36)
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	add_child(label)
