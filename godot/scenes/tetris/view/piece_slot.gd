extends Node2D
## Mini preview slot — renders a single piece kind (or empty) inside a fixed box.
## Used by both `next_queue` (one slot per upcoming piece) and `hold_slot`.

const PieceKind := preload("res://scripts/tetris/core/piece_kind.gd")
const Palette := preload("res://scripts/tetris/cell_palette.gd")

const CELL: int = 16
const SLOT_COLS: int = 4
const SLOT_ROWS: int = 3
const PADDING: int = 4

var _kind: int = -1
var _greyed: bool = false

func size_px() -> Vector2:
	return Vector2(SLOT_COLS * CELL + PADDING * 2, SLOT_ROWS * CELL + PADDING * 2)

func set_piece(kind: int, greyed: bool = false) -> void:
	_kind = kind
	_greyed = greyed
	queue_redraw()

func _draw() -> void:
	var sz: Vector2 = size_px()
	draw_rect(Rect2(Vector2.ZERO, sz), Palette.EMPTY, true)
	draw_rect(Rect2(Vector2.ZERO, sz), Palette.BORDER, false, 1.0)
	if _kind <= 0:
		return
	# Center the piece in the slot. Compute bounding box from rotation 0 cells.
	var cells: Array = PieceKind.cells(_kind, PieceKind.Rot.ZERO)
	var min_x: int = 99
	var max_x: int = -99
	var min_y: int = 99
	var max_y: int = -99
	for c in cells:
		min_x = min(min_x, c.x)
		max_x = max(max_x, c.x)
		min_y = min(min_y, c.y)
		max_y = max(max_y, c.y)
	var w: int = max_x - min_x + 1
	var h: int = max_y - min_y + 1
	var ox: float = PADDING + (SLOT_COLS - w) * 0.5 * CELL - min_x * CELL
	var oy: float = PADDING + (SLOT_ROWS - h) * 0.5 * CELL - min_y * CELL
	var color: Color = Palette.color_for(_kind)
	if _greyed:
		color = Color(color.r * 0.4, color.g * 0.4, color.b * 0.4, 1.0)
	for c in cells:
		var x: float = ox + c.x * CELL + 1
		var y: float = oy + c.y * CELL + 1
		draw_rect(Rect2(Vector2(x, y), Vector2(CELL - 2, CELL - 2)), color, true)
