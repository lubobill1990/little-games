extends CanvasLayer
## Wave-cleared interlude. Layer 5 (above world, below pause overlay). Shows a
## brief "WAVE N" banner; the parent times its dismissal in real time and
## ensures `state.tick()` is not called while we're visible.

var _label: Label


func _ready() -> void:
	layer = 5
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	_label = Label.new()
	_label.text = "WAVE 2"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.add_theme_font_size_override("font_size", 64)
	add_child(_label)
	visible = false


func show_with(wave: int) -> void:
	_label.text = "WAVE %d" % wave
	visible = true
