extends GutTest
## Board geometry, locking, and line clears (naive gravity).

const PieceKind := preload("res://scripts/tetris/core/piece_kind.gd")
const Piece := preload("res://scripts/tetris/core/piece.gd")
const Board := preload("res://scripts/tetris/core/board.gd")

func _fill_row(b: Board, row: int, kind: int = 1, gap_col: int = -1) -> void:
	for c in range(Board.COLS):
		if c == gap_col:
			continue
		b.set_cell(c, row, kind)

func test_new_board_is_all_empty() -> void:
	var b = Board.new()
	for r in range(Board.ROWS):
		for c in range(Board.COLS):
			assert_eq(b.get_cell(c, r), 0)

func test_in_bounds_rejects_outside() -> void:
	var b = Board.new()
	assert_true(b.in_bounds(0, 0))
	assert_true(b.in_bounds(9, 39))
	assert_false(b.in_bounds(-1, 0))
	assert_false(b.in_bounds(10, 0))
	assert_false(b.in_bounds(0, 40))
	assert_false(b.in_bounds(0, -1))

func test_is_blocked_walls_and_floor() -> void:
	var b = Board.new()
	# Empty cell inside grid: not blocked.
	assert_false(b.is_blocked(5, 20))
	# Side walls and floor: blocked.
	assert_true(b.is_blocked(-1, 20))
	assert_true(b.is_blocked(10, 20))
	assert_true(b.is_blocked(5, 40))
	# Buffer above row 0: not blocked (allows piece bounding box to extend up).
	assert_false(b.is_blocked(5, -1))

func test_can_place_blocks_on_filled_cell() -> void:
	var b = Board.new()
	var p = Piece.spawn(PieceKind.Kind.O)
	assert_true(b.can_place(p, p.origin, p.rot))
	# Drop one of the O's cells onto a filled spot.
	var cs = p.cells()
	b.set_cell(cs[0].x, cs[0].y, PieceKind.Kind.I)
	assert_false(b.can_place(p, p.origin, p.rot))

func test_can_place_rejects_out_of_bounds() -> void:
	var b = Board.new()
	var p = Piece.spawn(PieceKind.Kind.I)
	# Way left.
	assert_false(b.can_place(p, Vector2i(-5, 19), 0))
	# Below floor.
	assert_false(b.can_place(p, Vector2i(3, 39), 0))

func test_lock_piece_writes_kind_into_grid() -> void:
	var b = Board.new()
	var p = Piece.spawn(PieceKind.Kind.T)
	p.origin = Vector2i(3, 38)  # T pointing up; cells span row 38..39.
	b.lock_piece(p)
	for c in p.cells():
		assert_eq(b.get_cell(c.x, c.y), PieceKind.Kind.T,
				"cell %d,%d should be T" % [c.x, c.y])

func test_full_rows_detects_complete_lines() -> void:
	var b = Board.new()
	_fill_row(b, 39)
	_fill_row(b, 37, 2)  # gap_col defaulted to -1 → fully filled
	_fill_row(b, 36, 1, 5)  # gap at col 5 → NOT full
	var rows = b.full_rows()
	rows.sort()
	assert_eq(rows, [37, 39])

func test_clear_rows_single_at_bottom() -> void:
	var b = Board.new()
	_fill_row(b, 39, 1)
	# Place a marker on row 38 col 0.
	b.set_cell(0, 38, PieceKind.Kind.J)
	var n = b.clear_full_rows()
	assert_eq(n, 1)
	# After clear, the marker should drop to row 39.
	assert_eq(b.get_cell(0, 39), PieceKind.Kind.J)
	# Row 38 should be empty everywhere now.
	for c in range(Board.COLS):
		assert_eq(b.get_cell(c, 38), 0, "row 38 col %d should be empty" % c)

func test_clear_rows_double() -> void:
	var b = Board.new()
	_fill_row(b, 39, 1)
	_fill_row(b, 38, 2)
	b.set_cell(0, 37, PieceKind.Kind.L)
	var n = b.clear_full_rows()
	assert_eq(n, 2)
	assert_eq(b.get_cell(0, 39), PieceKind.Kind.L)
	for c in range(Board.COLS):
		assert_eq(b.get_cell(c, 38), 0)

func test_clear_rows_tetris_four_with_gap_above() -> void:
	var b = Board.new()
	for r in range(36, 40):
		_fill_row(b, r, 1)
	b.set_cell(3, 35, PieceKind.Kind.S)
	var n = b.clear_full_rows()
	assert_eq(n, 4)
	# Single marker should now be at row 39 col 3.
	assert_eq(b.get_cell(3, 39), PieceKind.Kind.S)
	# Everything else empty.
	for r in range(Board.ROWS):
		for c in range(Board.COLS):
			if r == 39 and c == 3:
				continue
			assert_eq(b.get_cell(c, r), 0, "expected empty at %d,%d" % [c, r])

func test_clear_rows_non_adjacent_preserves_middle() -> void:
	# A "split" clear: row 39 and row 37 both full, row 38 has stuff that
	# should fall to row 39 after the two clears (naive gravity, no cascade).
	var b = Board.new()
	_fill_row(b, 39, 1)
	_fill_row(b, 37, 1)
	b.set_cell(0, 38, PieceKind.Kind.Z)
	b.set_cell(9, 38, PieceKind.Kind.Z)
	b.set_cell(4, 36, PieceKind.Kind.O)
	var n = b.clear_full_rows()
	assert_eq(n, 2)
	# After the two clears: row 38 (was 36) holds the O at col 4; row 39 holds the Zs at cols 0 and 9.
	assert_eq(b.get_cell(0, 39), PieceKind.Kind.Z)
	assert_eq(b.get_cell(9, 39), PieceKind.Kind.Z)
	assert_eq(b.get_cell(4, 38), PieceKind.Kind.O)

func test_clear_full_rows_with_no_full_rows_is_noop() -> void:
	var b = Board.new()
	b.set_cell(0, 39, PieceKind.Kind.I)
	var n = b.clear_full_rows()
	assert_eq(n, 0)
	assert_eq(b.get_cell(0, 39), PieceKind.Kind.I)

func test_snapshot_and_restore_round_trip() -> void:
	var b = Board.new()
	b.set_cell(2, 30, PieceKind.Kind.J)
	b.set_cell(7, 35, PieceKind.Kind.L)
	var snap = b.snapshot()
	b.set_cell(2, 30, 0)
	b.set_cell(0, 0, PieceKind.Kind.I)
	b.restore(snap)
	assert_eq(b.get_cell(2, 30), PieceKind.Kind.J)
	assert_eq(b.get_cell(7, 35), PieceKind.Kind.L)
	assert_eq(b.get_cell(0, 0), 0)

func test_reset_clears_everything() -> void:
	var b = Board.new()
	_fill_row(b, 39)
	b.reset()
	for c in range(Board.COLS):
		assert_eq(b.get_cell(c, 39), 0)
