extends VBoxContainer
## Five vertically stacked piece slots showing the next queue from `state.next_queue(5)`.

const PieceSlot := preload("res://scenes/tetris/view/piece_slot.gd")

var _slots: Array = []

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	for i in range(5):
		var slot := PieceSlot.new()
		add_child(slot)
		slot.custom_minimum_size = slot.size_px()
		_slots.append(slot)

func update_from(state) -> void:
	var queue: Array = state.next_queue(5)
	for i in range(_slots.size()):
		var kind: int = queue[i] if i < queue.size() else -1
		_slots[i].set_piece(kind, false)
