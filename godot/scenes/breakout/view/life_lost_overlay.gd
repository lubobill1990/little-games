extends CanvasLayer
## Brief "Get ready" overlay shown for ~800 ms after a life loss while the
## ball returns to sticky. The scene drives visibility — this overlay only
## paints. Layer 9 = below pause/game-over so they take precedence if the
## player paused mid-life-loss.

var _label: Label

func _ready() -> void:
	layer = 9
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.4)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	_label = Label.new()
	_label.text = "GET READY"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.add_theme_font_size_override("font_size", 36)
	add_child(_label)
	visible = false

func set_lives(lives_remaining: int) -> void:
	if lives_remaining > 0:
		_label.text = "GET READY — %d LIVES" % lives_remaining
	else:
		_label.text = "GET READY"
