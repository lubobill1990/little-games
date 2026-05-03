extends VBoxContainer
## Breakout HUD: score, lives, level. Updated by parent on every visible
## state change.

const Palette := preload("res://scripts/breakout/brick_palette.gd")

var _score_label: Label
var _lives_label: Label
var _level_label: Label

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_score_label = _make_label("Score: 0", 28)
	_lives_label = _make_label("Lives: 3", 20)
	_level_label = _make_label("Level: 1", 18)
	add_child(_score_label)
	add_child(_lives_label)
	add_child(_level_label)

func _make_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Palette.HUD_TEXT)
	return l

func update_from_snapshot(snap: Dictionary, level_index: int = 1) -> void:
	_score_label.text = "Score: %d" % int(snap.get("score", 0))
	_lives_label.text = "Lives: %d" % int(snap.get("lives", 0))
	_level_label.text = "Level: %d" % level_index
