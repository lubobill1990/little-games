extends Node2D
## 2048 background grid: draws the board's empty-cell rectangles. Tiles paint
## on top in the same Node2D parent, so they naturally cover this background.
##
## Sizing is driven by `configure(size_n, cell_px, gap)` from g2048.gd; the
## grid never measures itself from layout.

const Palette := preload("res://scripts/g2048/tile_palette.gd")

var _n: int = 4
var _cell_px: float = 80.0
var _gap: float = 6.0


func configure(n: int, cell_px: float, gap: float) -> void:
	_n = n
	_cell_px = cell_px
	_gap = gap
	queue_redraw()


func board_pixel_size() -> Vector2:
	var w: float = _n * _cell_px
	return Vector2(w, w)


func _draw() -> void:
	var w: float = _n * _cell_px
	# Whole-board background.
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, w)), Palette.board_bg_color(), true)
	# Empty-cell tiles (lighter rectangles inside the board).
	for r in _n:
		for c in _n:
			var cx: float = c * _cell_px + _cell_px * 0.5
			var cy: float = r * _cell_px + _cell_px * 0.5
			var ew: float = _cell_px - _gap
			var eh: float = _cell_px - _gap
			var rect := Rect2(cx - ew * 0.5, cy - eh * 0.5, ew, eh)
			draw_rect(rect, Palette.empty_cell_color(), true)
