extends Control
## Invaders HUD: score (top-left), wave (top-center), lives as small ship icons
## (top-right). Updated by parent on every visible state change.

const InvadersConfig := preload("res://scripts/invaders/core/invaders_config.gd")
const Palette := preload("res://scripts/invaders/invaders_palette.gd")

var _cfg: InvadersConfig
var _score_label: Label
var _best_label: Label
var _wave_label: Label
var _lives_box: HBoxContainer
var _last_lives: int = -1


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_bottom = 56.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_label = Label.new()
	_score_label.text = "Score: 0"
	_score_label.add_theme_font_size_override("font_size", 22)
	_score_label.add_theme_color_override("font_color", Palette.HUD_TEXT)
	_score_label.position = Vector2(16, 12)
	add_child(_score_label)
	_best_label = Label.new()
	_best_label.text = "Best: 0"
	_best_label.add_theme_font_size_override("font_size", 14)
	_best_label.add_theme_color_override("font_color", Palette.HUD_TEXT)
	_best_label.position = Vector2(16, 38)
	add_child(_best_label)
	_wave_label = Label.new()
	_wave_label.text = "Wave 1"
	_wave_label.add_theme_font_size_override("font_size", 22)
	_wave_label.add_theme_color_override("font_color", Palette.HUD_TEXT)
	_wave_label.anchor_left = 0.5
	_wave_label.anchor_right = 0.5
	_wave_label.position = Vector2(-40, 12)
	add_child(_wave_label)
	_lives_box = HBoxContainer.new()
	_lives_box.anchor_left = 1.0
	_lives_box.anchor_right = 1.0
	_lives_box.position = Vector2(-120, 12)
	_lives_box.add_theme_constant_override("separation", 4)
	add_child(_lives_box)


func configure(cfg: InvadersConfig) -> void:
	_cfg = cfg


func update_from_snapshot(snap: Dictionary, best_score: int = 0) -> void:
	_score_label.text = "Score: %d" % int(snap.get("score", 0))
	_best_label.text = "Best: %d" % best_score
	_wave_label.text = "Wave %d" % int(snap.get("wave", 1))
	var lives: int = int(snap.get("lives", 0))
	if lives != _last_lives:
		_rebuild_lives_icons(lives)
		_last_lives = lives


func _rebuild_lives_icons(count: int) -> void:
	for child in _lives_box.get_children():
		_lives_box.remove_child(child)
		child.queue_free()
	for i in range(count):
		var r := ColorRect.new()
		r.color = Palette.PLAYER
		r.custom_minimum_size = Vector2(20, 10)
		_lives_box.add_child(r)
