extends Control
## Single piece slot showing currently-held piece. Greys it out when hold is locked
## (player already used hold this piece).

const PieceSlot := preload("res://scenes/tetris/view/piece_slot.gd")

var _slot

func _ready() -> void:
	_slot = PieceSlot.new()
	add_child(_slot)
	custom_minimum_size = _slot.size_px()

func update_from(state) -> void:
	var held: int = state.held_piece()
	_slot.set_piece(held, not state.can_hold() and held > 0)
