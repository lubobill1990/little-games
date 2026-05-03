extends GutTest
## Unit test for the pure scoring fn in tetris_ai.gd. No piece logic, no
## planner, no game state — just feeds hand-crafted boards into score_board
## and asserts the heuristic reads them correctly.

const Board := preload("res://scripts/tetris/core/board.gd")
const TetrisAI := preload("res://scripts/e2e/tetris_ai.gd")


func _empty_cells() -> PackedInt32Array:
	var c: PackedInt32Array = PackedInt32Array()
	c.resize(Board.COLS * Board.ROWS)
	return c


func _set(cells: PackedInt32Array, col: int, row: int, kind: int = 1) -> void:
	cells[Board.idx(col, row)] = kind


func test_empty_board_zero_features() -> void:
	var c := _empty_cells()
	assert_eq(int(TetrisAI.column_heights(c)[0]), 0)
	assert_eq(TetrisAI.count_holes(c, TetrisAI.column_heights(c)), 0)
	# Score on an empty board with 0 lines cleared = 0 (all features zero).
	assert_almost_eq(TetrisAI.score_board(c, 0), 0.0, 0.0001)


func test_column_height_measured_from_floor() -> void:
	var c := _empty_cells()
	# Place a single block at the floor of column 0 (row ROWS-1).
	_set(c, 0, Board.ROWS - 1)
	var h := TetrisAI.column_heights(c)
	assert_eq(int(h[0]), 1, "single floor block = height 1")
	# Add another at row ROWS-3: height should jump to 3 (top filled is row ROWS-3).
	_set(c, 0, Board.ROWS - 3)
	h = TetrisAI.column_heights(c)
	assert_eq(int(h[0]), 3, "top filled at row ROWS-3 = height 3")


func test_holes_counts_empty_cells_below_top() -> void:
	var c := _empty_cells()
	# Column 0: filled at ROWS-1 and ROWS-3, empty at ROWS-2 → 1 hole.
	_set(c, 0, Board.ROWS - 1)
	_set(c, 0, Board.ROWS - 3)
	var h := TetrisAI.column_heights(c)
	assert_eq(TetrisAI.count_holes(c, h), 1, "single hole between two filled rows")


func test_higher_aggregate_lowers_score() -> void:
	# Two boards, identical except one is taller. The taller one should score
	# strictly lower (W_AGG_HEIGHT is negative).
	var low := _empty_cells()
	_set(low, 0, Board.ROWS - 1)
	var hi := _empty_cells()
	_set(hi, 0, Board.ROWS - 1)
	_set(hi, 0, Board.ROWS - 2)
	_set(hi, 0, Board.ROWS - 3)
	assert_lt(TetrisAI.score_board(hi, 0), TetrisAI.score_board(low, 0),
		"taller stack scores lower")


func test_lines_cleared_increases_score() -> void:
	var c := _empty_cells()
	# Compare same board with cleared=0 vs cleared=1 — the cleared variant
	# should be strictly higher.
	var s0: float = TetrisAI.score_board(c, 0)
	var s1: float = TetrisAI.score_board(c, 1)
	assert_gt(s1, s0, "lines_cleared=1 > lines_cleared=0")
	assert_gt(TetrisAI.score_board(c, 4), TetrisAI.score_board(c, 1),
		"tetris (4 lines) > single")


func test_holes_lower_score() -> void:
	# Same height profile, but one has a hole.
	var solid := _empty_cells()
	_set(solid, 0, Board.ROWS - 1)
	_set(solid, 0, Board.ROWS - 2)
	_set(solid, 0, Board.ROWS - 3)
	var holey := _empty_cells()
	_set(holey, 0, Board.ROWS - 1)
	_set(holey, 0, Board.ROWS - 3)
	# `holey` has the same height (3) but a hole at ROWS-2.
	assert_lt(TetrisAI.score_board(holey, 0), TetrisAI.score_board(solid, 0),
		"board with a hole scores strictly lower than the solid one")
