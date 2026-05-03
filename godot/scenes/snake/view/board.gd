extends Node2D
## Snake board renderer. Two _draw layers folded into one Node2D for simplicity:
## the grid lines (cheap to repaint) and the snake/food cells. Both repaint
## together on queue_redraw(); per-frame this is dominated by the snake length
## (≤ grid_w * grid_h cells), well within budget for 60 fps.

const Palette := preload("res://scripts/snake/cell_palette.gd")

var _grid_w: int = 20
var _grid_h: int = 20
var _walls: bool = true
var _cell_size: float = 16.0
var _snake_cells: Array = []   # Array of [x, y] pairs (snapshot format).
var _food_cell: Vector2i = Vector2i(-1, -1)

func configure(grid_w: int, grid_h: int, walls: bool) -> void:
	_grid_w = grid_w
	_grid_h = grid_h
	_walls = walls
	queue_redraw()

func set_cell_size(px: float) -> void:
	if not is_equal_approx(px, _cell_size):
		_cell_size = px
		queue_redraw()

func update_from_snapshot(snap: Dictionary) -> void:
	_snake_cells = snap.get("snake", [])
	var f: Array = snap.get("food", [-1, -1])
	if f.size() >= 2:
		_food_cell = Vector2i(int(f[0]), int(f[1]))
	queue_redraw()

func board_pixel_size() -> Vector2:
	return Vector2(_grid_w * _cell_size, _grid_h * _cell_size)

func _draw() -> void:
	var w: float = _grid_w * _cell_size
	var h: float = _grid_h * _cell_size
	# Background.
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Palette.BG, true)
	# Grid lines.
	for c in range(_grid_w + 1):
		var x: float = c * _cell_size
		draw_line(Vector2(x, 0), Vector2(x, h), Palette.GRID_LINE, 1.0)
	for r in range(_grid_h + 1):
		var y: float = r * _cell_size
		draw_line(Vector2(0, y), Vector2(w, y), Palette.GRID_LINE, 1.0)
	# Walls (only when configured) — thicker outline.
	if _walls:
		draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Palette.WALL, false, 2.0)
	# Food.
	if _food_cell.x >= 0:
		_draw_cell(_food_cell.x, _food_cell.y, Palette.FOOD, 0.20)
	# Snake. Head distinguished by a slightly brighter color.
	for i in _snake_cells.size():
		var p: Array = _snake_cells[i]
		var color: Color = Palette.SNAKE_HEAD if i == 0 else Palette.SNAKE_BODY
		_draw_cell(int(p[0]), int(p[1]), color, 0.10)

func _draw_cell(cx: int, cy: int, color: Color, inset_frac: float) -> void:
	var inset: float = _cell_size * inset_frac
	var pos: Vector2 = Vector2(cx * _cell_size + inset, cy * _cell_size + inset)
	var sz: Vector2 = Vector2(_cell_size - 2.0 * inset, _cell_size - 2.0 * inset)
	draw_rect(Rect2(pos, sz), color, true)
