extends Control
## Bootstrap placeholder. Replaced by the real game-selection menu in task #6.

@onready var label: Label = $CenterContainer/VBoxContainer/Title

func _ready() -> void:
	label.text = "%s — bootstrap\nMain menu lands in task #6." % GameInfo.PROJECT_NAME
