extends Control
## Bootstrap placeholder. Replaced by the real game-selection menu in task #6.

@onready var label: Label = $CenterContainer/VBoxContainer/Title
@onready var play_button: Button = $CenterContainer/VBoxContainer/PlayTetris

func _ready() -> void:
	label.text = "%s — bootstrap\nMain menu lands in task #6." % GameInfo.PROJECT_NAME
	play_button.pressed.connect(_on_play_pressed)
	play_button.grab_focus()

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/tetris/tetris.tscn")
