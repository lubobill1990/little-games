extends VBoxContainer
## 2048 HUD — current score and best (best is placeholder until polish task).

var _score_label: Label
var _best_label: Label


func _ready() -> void:
	_score_label = Label.new()
	_score_label.text = "Score: 0"
	_score_label.add_theme_font_size_override("font_size", 24)
	add_child(_score_label)
	_best_label = Label.new()
	_best_label.text = "Best: --"
	_best_label.add_theme_font_size_override("font_size", 18)
	add_child(_best_label)


func update_from_snapshot(snap: Dictionary) -> void:
	if _score_label == null:
		return
	_score_label.text = "Score: %d" % int(snap.get("score", 0))
	# Best is wired in the polish task (#21). Show a static placeholder for now.
	_best_label.text = "Best: --"
