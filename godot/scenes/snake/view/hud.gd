extends VBoxContainer
## Snake HUD: score, level, step rate, difficulty. Updated by parent on every
## visible state change.

const Palette := preload("res://scripts/snake/cell_palette.gd")

var _score_label: Label
var _level_label: Label
var _step_label: Label
var _difficulty_label: Label

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_score_label = _make_label("Score: 0", 28)
	_level_label = _make_label("Level: 1", 18)
	_step_label = _make_label("Step: 200ms", 14)
	_difficulty_label = _make_label("", 14)
	add_child(_score_label)
	add_child(_level_label)
	add_child(_step_label)
	add_child(_difficulty_label)

func _make_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Palette.HUD_TEXT)
	return l

func update_from_snapshot(snap: Dictionary) -> void:
	_score_label.text = "Score: %d" % int(snap.get("score", 0))
	_level_label.text = "Level: %d" % int(snap.get("level", 1))
	_step_label.text = "Step: %dms" % int(snap.get("step_ms", 0))

func set_difficulty(title: String) -> void:
	_difficulty_label.text = "Difficulty: %s" % title
