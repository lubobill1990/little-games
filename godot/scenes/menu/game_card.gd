extends Button
## Single tile in MainMenu. Decoupled from registry/runtime — all it knows is
## the descriptor it was bound to and emits a typed pressed signal.

const GameDescriptor := preload("res://scripts/core/game/game_descriptor.gd")

signal game_chosen(descriptor: GameDescriptor)

var _descriptor: GameDescriptor

func bind(descriptor: GameDescriptor) -> void:
	_descriptor = descriptor
	text = descriptor.title
	custom_minimum_size = Vector2(220, 80)
	add_theme_font_size_override("font_size", 24)
	pressed.connect(func() -> void: game_chosen.emit(_descriptor))

func descriptor() -> GameDescriptor:
	return _descriptor
