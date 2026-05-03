extends VBoxContainer
## 2048 HUD — score, best, undo button.

signal undo_pressed()

var _score_label: Label
var _best_label: Label
var _undo_button: Button


func _ready() -> void:
	_score_label = Label.new()
	_score_label.text = "Score: 0"
	_score_label.add_theme_font_size_override("font_size", 24)
	add_child(_score_label)
	_best_label = Label.new()
	_best_label.text = "Best: 0"
	_best_label.add_theme_font_size_override("font_size", 18)
	add_child(_best_label)
	_undo_button = Button.new()
	_undo_button.text = "Undo (Z)"
	_undo_button.disabled = true
	_undo_button.pressed.connect(_on_undo_button_pressed)
	add_child(_undo_button)


func update_from_snapshot(snap: Dictionary) -> void:
	if _score_label == null:
		return
	_score_label.text = "Score: %d" % int(snap.get("score", 0))


func update_best(value: int) -> void:
	if _best_label == null:
		return
	_best_label.text = "Best: %d" % value


func set_undo_enabled(enabled: bool) -> void:
	if _undo_button == null:
		return
	_undo_button.disabled = not enabled


func _on_undo_button_pressed() -> void:
	undo_pressed.emit()
