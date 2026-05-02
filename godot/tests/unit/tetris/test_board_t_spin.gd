extends GutTest
## T-spin classification: 3-corner rule + kick-5 override.
##
## Fixtures are constructed with the T already placed at its post-rotation
## position; we assert classify() against the surrounding corners.

const PieceKind := preload("res://scripts/tetris/core/piece_kind.gd")
const Piece := preload("res://scripts/tetris/core/piece.gd")
const Board := preload("res://scripts/tetris/core/board.gd")
const TSpin := preload("res://scripts/tetris/core/t_spin.gd")

func _t_at(origin: Vector2i, rot: int) -> Piece:
	var p = Piece.spawn(PieceKind.Kind.T)
	p.origin = origin
	p.rot = rot
	return p

# Helper: fill explicit corner cells around a T's bounding box.
func _fill(b: Board, origin: Vector2i, offsets: Array) -> void:
	for off in offsets:
		b.set_cell(origin.x + off.x, origin.y + off.y, PieceKind.Kind.J)

func test_non_t_piece_is_never_t_spin() -> void:
	var b = Board.new()
	var p = Piece.spawn(PieceKind.Kind.J)
	assert_eq(TSpin.classify(p, 0, b), TSpin.NONE)

func test_no_corners_filled_is_none() -> void:
	var b = Board.new()
	var p = _t_at(Vector2i(3, 30), 0)
	assert_eq(TSpin.classify(p, 0, b), TSpin.NONE)

func test_two_corners_is_none() -> void:
	# T pointing up: fill SW and SE only (2 corners) → no T-spin.
	var b = Board.new()
	var origin = Vector2i(3, 30)
	_fill(b, origin, [Vector2i(0, 2), Vector2i(2, 2)])
	var p = _t_at(origin, 0)
	assert_eq(TSpin.classify(p, 0, b), TSpin.NONE)

func test_full_when_both_fronts_plus_one_back_for_rot_zero() -> void:
	# T points up. Fronts = NW + NE, backs = SW + SE. Fill both fronts + one back.
	var b = Board.new()
	var origin = Vector2i(3, 30)
	_fill(b, origin, [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 2)])
	var p = _t_at(origin, 0)
	assert_eq(TSpin.classify(p, 0, b), TSpin.FULL)

func test_mini_when_only_one_front_plus_two_backs_for_rot_zero() -> void:
	# T points up. Fill 1 front (NW) + both backs.
	var b = Board.new()
	var origin = Vector2i(3, 30)
	_fill(b, origin, [Vector2i(0, 0), Vector2i(0, 2), Vector2i(2, 2)])
	var p = _t_at(origin, 0)
	assert_eq(TSpin.classify(p, 0, b), TSpin.MINI)

func test_full_for_rot_r_with_both_right_corners() -> void:
	# T points right. Fronts = NE + SE.
	var b = Board.new()
	var origin = Vector2i(3, 30)
	_fill(b, origin, [Vector2i(2, 0), Vector2i(2, 2), Vector2i(0, 0)])
	var p = _t_at(origin, 1)
	assert_eq(TSpin.classify(p, 1, b), TSpin.FULL)

func test_mini_for_rot_r_with_only_left_back_corners() -> void:
	# T points right. Backs = NW + SW. Fill backs + 1 front (NE).
	var b = Board.new()
	var origin = Vector2i(3, 30)
	_fill(b, origin, [Vector2i(0, 0), Vector2i(0, 2), Vector2i(2, 0)])
	var p = _t_at(origin, 1)
	assert_eq(TSpin.classify(p, 1, b), TSpin.MINI)

func test_rot_two_full_when_both_bottom_corners_plus_top() -> void:
	# T points down. Fronts = SW + SE.
	var b = Board.new()
	var origin = Vector2i(3, 30)
	_fill(b, origin, [Vector2i(0, 2), Vector2i(2, 2), Vector2i(0, 0)])
	var p = _t_at(origin, 2)
	assert_eq(TSpin.classify(p, 2, b), TSpin.FULL)

func test_rot_l_full_when_both_left_corners_plus_back() -> void:
	# T points left. Fronts = NW + SW.
	var b = Board.new()
	var origin = Vector2i(3, 30)
	_fill(b, origin, [Vector2i(0, 0), Vector2i(0, 2), Vector2i(2, 2)])
	var p = _t_at(origin, 3)
	assert_eq(TSpin.classify(p, 3, b), TSpin.FULL)

func test_kick_five_promotes_mini_to_full() -> void:
	# Same fixture as the rot-0 mini case (1 front + 2 backs), but kick_index = 4.
	var b = Board.new()
	var origin = Vector2i(3, 30)
	_fill(b, origin, [Vector2i(0, 0), Vector2i(0, 2), Vector2i(2, 2)])
	var p = _t_at(origin, 0)
	assert_eq(TSpin.classify(p, 4, b), TSpin.FULL)

func test_kick_five_does_not_create_t_spin_when_corners_under_three() -> void:
	# Kick-5 still requires the 3-corner pre-gate.
	var b = Board.new()
	var origin = Vector2i(3, 30)
	_fill(b, origin, [Vector2i(0, 0), Vector2i(0, 2)])
	var p = _t_at(origin, 0)
	assert_eq(TSpin.classify(p, 4, b), TSpin.NONE)

func test_walls_count_as_corners() -> void:
	# Place T flush against the left wall; col -1 is "blocked" (out-of-bounds).
	var b = Board.new()
	var origin = Vector2i(-1, 30)
	# Fill only one in-bounds corner (SE at col 1 row 32).
	b.set_cell(1, 32, PieceKind.Kind.J)
	# Corners NW(-1,30) and SW(-1,32) are out-of-bounds → blocked.
	# So total = 3 (NW, SW, SE) → at least 3.
	# Fronts for rot 0 = NW + NE. NW is blocked (wall), NE is empty.
	# front_filled = 1, back_filled = 2 → MINI.
	var p = _t_at(origin, 0)
	assert_eq(TSpin.classify(p, 0, b), TSpin.MINI)

func test_floor_counts_as_corner() -> void:
	# Place T such that SW/SE corners are below the floor (row 40).
	var b = Board.new()
	var origin = Vector2i(3, 38)  # corners at rows 38 and 40; row 40 is OOB.
	# Fill NW so we have 3 blocked corners (NW filled, SW + SE out-of-bounds).
	b.set_cell(3, 38, PieceKind.Kind.J)
	var p = _t_at(origin, 0)
	# Fronts (rot 0) = NW + NE. NW filled, NE empty. Backs both OOB. → MINI.
	assert_eq(TSpin.classify(p, 0, b), TSpin.MINI)
