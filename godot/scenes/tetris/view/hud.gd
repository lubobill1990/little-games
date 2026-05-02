extends VBoxContainer
## Score / Level / Lines readout. Driven by `update_from(state)`.

@onready var _score: Label = $ScoreLabel
@onready var _level: Label = $LevelLabel
@onready var _lines: Label = $LinesLabel

func update_from(state) -> void:
	_score.text = "SCORE\n%d" % state.score()
	_level.text = "LEVEL\n%d" % state.level()
	_lines.text = "LINES\n%d" % state.lines_cleared()
