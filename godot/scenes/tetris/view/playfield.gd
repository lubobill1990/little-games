extends Node2D
## Renders the visible 10×20 portion of TetrisBoard, the active piece, and ghost.
##
## Three logical layers, all drawn in this single Node2D for simplicity:
##   1. Static board cells + grid + border. Repainted only when `dirty_board`.
##   2. Ghost piece.
##   3. Active piece.
## Per-cell flash modulation (line-clear animation) is overlaid on the matching
## rows of layer 1 — set `_flash_rows` and `_flash_alpha`.
##
## The view is purely a sink: it reads from a `TetrisGameState` set via
## `bind(state)`. It does not mutate state and does not call OS APIs.

const Board := preload("res://scripts/tetris/core/board.gd")
const PieceKind := preload("res://scripts/tetris/core/piece_kind.gd")
const Palette := preload("res://scripts/tetris/cell_palette.gd")

const CELL: int = 28
const VISIBLE_ROWS: int = 20
const COLS: int = 10
const PADDING: int = 4

var _state = null  # TetrisGameState; loose-typed to avoid circular preload
var _accepts_input: bool = true
var _flash_rows: Array = []
var _flash_alpha: float = 0.0

func size_px() -> Vector2:
	return Vector2(COLS * CELL + PADDING * 2, VISIBLE_ROWS * CELL + PADDING * 2)

func bind(state) -> void:
	_state = state
	queue_redraw()

func set_flash(rows: Array, alpha: float) -> void:
	_flash_rows = rows
	_flash_alpha = clamp(alpha, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	# Background + border.
	var sz: Vector2 = size_px()
	draw_rect(Rect2(Vector2.ZERO, sz), Palette.EMPTY, true)
	draw_rect(Rect2(Vector2.ZERO, sz), Palette.BORDER, false, 2.0)

	# Grid lines.
	for c in range(1, COLS):
		var x: float = PADDING + c * CELL
		draw_line(Vector2(x, PADDING), Vector2(x, PADDING + VISIBLE_ROWS * CELL), Palette.GRID_LINE, 1.0)
	for r in range(1, VISIBLE_ROWS):
		var y: float = PADDING + r * CELL
		draw_line(Vector2(PADDING, y), Vector2(PADDING + COLS * CELL, y), Palette.GRID_LINE, 1.0)

	if _state == null:
		return

	# Locked cells.
	var board = _state.board
	for vis_r in range(VISIBLE_ROWS):
		var board_row: int = Board.VISIBLE_TOP + vis_r
		for col in range(COLS):
			var k: int = board.get_cell(col, board_row)
			if k > 0:
				_draw_cell(col, vis_r, Palette.color_for(k))

	# Per-row flash overlay (line-clear).
	if _flash_alpha > 0.0 and not _flash_rows.is_empty():
		for board_row in _flash_rows:
			var vis_r: int = board_row - Board.VISIBLE_TOP
			if vis_r < 0 or vis_r >= VISIBLE_ROWS:
				continue
			var rect := Rect2(Vector2(PADDING, PADDING + vis_r * CELL), Vector2(COLS * CELL, CELL))
			draw_rect(rect, Color(1, 1, 1, _flash_alpha), true)

	# Ghost + active piece (only when game is live).
	var piece = _state.current_piece()
	if piece != null and not _state.is_game_over():
		var ghost_origin: Vector2i = _state.ghost_position()
		for off in PieceKind.cells(piece.kind, piece.rot):
			var col: int = ghost_origin.x + off.x
			var row: int = ghost_origin.y + off.y
			var vis_r: int = row - Board.VISIBLE_TOP
			if vis_r >= 0 and vis_r < VISIBLE_ROWS:
				_draw_cell(col, vis_r, Palette.ghost_color(piece.kind))
		for cell in piece.cells():
			var vis_r: int = cell.y - Board.VISIBLE_TOP
			if vis_r >= 0 and vis_r < VISIBLE_ROWS:
				_draw_cell(cell.x, vis_r, Palette.color_for(piece.kind))

func _draw_cell(col: int, vis_row: int, color: Color) -> void:
	var x: float = PADDING + col * CELL + 1
	var y: float = PADDING + vis_row * CELL + 1
	draw_rect(Rect2(Vector2(x, y), Vector2(CELL - 2, CELL - 2)), color, true)
