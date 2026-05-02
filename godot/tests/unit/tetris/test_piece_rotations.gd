extends GutTest
## Verifies SRS rotation cell layouts for every (kind, rotation) pair.
##
## We don't trust direction labels — we assert resulting absolute cells against
## hand-checked reference shapes. The reference shapes here are the SRS
## Guideline; mistakes get caught the moment kicks or T-spin tests run.

const PieceKind := preload("res://scripts/tetris/core/piece_kind.gd")
const Piece := preload("res://scripts/tetris/core/piece.gd")

func _sorted_cells(arr: Array) -> Array:
	# Sort cells deterministically so equality is order-independent.
	var keyed: Array = []
	for c in arr:
		keyed.append([c.y, c.x])
	keyed.sort()
	var out: Array = []
	for k in keyed:
		out.append(Vector2i(k[1], k[0]))
	return out

func test_each_kind_each_rotation_has_four_cells() -> void:
	for kind in PieceKind.KINDS:
		for rot in [0, 1, 2, 3]:
			var cells = PieceKind.cells(kind, rot)
			assert_eq(cells.size(), 4, "kind=%d rot=%d should have 4 cells" % [kind, rot])

func test_rotate_cw_and_ccw_are_inverses() -> void:
	for r in [0, 1, 2, 3]:
		assert_eq(PieceKind.rotate_ccw(PieceKind.rotate_cw(r)), r)
		assert_eq(PieceKind.rotate_cw(PieceKind.rotate_ccw(r)), r)

func test_rotate_cw_cycles_zero_r_two_l() -> void:
	var seq: Array = []
	var r: int = 0
	for _i in 4:
		seq.append(r)
		r = PieceKind.rotate_cw(r)
	assert_eq(seq, [0, 1, 2, 3])

func test_o_piece_invariant_under_rotation() -> void:
	var ref = _sorted_cells(PieceKind.cells(PieceKind.Kind.O, 0))
	for rot in [1, 2, 3]:
		assert_eq(_sorted_cells(PieceKind.cells(PieceKind.Kind.O, rot)), ref,
				"O-piece must be rotation-invariant")

func test_i_piece_horizontal_in_state_zero() -> void:
	# State 0: row 1, cols 0..3. Standard SRS.
	assert_eq(_sorted_cells(PieceKind.cells(PieceKind.Kind.I, 0)), _sorted_cells([
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
	]))

func test_i_piece_vertical_in_state_r() -> void:
	# State R: col 2, rows 0..3.
	assert_eq(_sorted_cells(PieceKind.cells(PieceKind.Kind.I, 1)), _sorted_cells([
		Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3),
	]))

func test_t_piece_pointing_directions() -> void:
	# State 0: T points up (top middle filled, bottom row of 3).
	assert_eq(_sorted_cells(PieceKind.cells(PieceKind.Kind.T, 0)), _sorted_cells([
		Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
	]))
	# State R: T points right.
	assert_eq(_sorted_cells(PieceKind.cells(PieceKind.Kind.T, 1)), _sorted_cells([
		Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2),
	]))
	# State 2: T points down.
	assert_eq(_sorted_cells(PieceKind.cells(PieceKind.Kind.T, 2)), _sorted_cells([
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2),
	]))
	# State L: T points left.
	assert_eq(_sorted_cells(PieceKind.cells(PieceKind.Kind.T, 3)), _sorted_cells([
		Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2),
	]))

func test_s_piece_states() -> void:
	assert_eq(_sorted_cells(PieceKind.cells(PieceKind.Kind.S, 0)), _sorted_cells([
		Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1),
	]))
	assert_eq(_sorted_cells(PieceKind.cells(PieceKind.Kind.S, 2)), _sorted_cells([
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2),
	]))

func test_z_piece_states() -> void:
	assert_eq(_sorted_cells(PieceKind.cells(PieceKind.Kind.Z, 0)), _sorted_cells([
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1),
	]))

func test_j_piece_states() -> void:
	# J state 0: hook on top-left.
	assert_eq(_sorted_cells(PieceKind.cells(PieceKind.Kind.J, 0)), _sorted_cells([
		Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
	]))

func test_l_piece_states() -> void:
	# L state 0: hook on top-right.
	assert_eq(_sorted_cells(PieceKind.cells(PieceKind.Kind.L, 0)), _sorted_cells([
		Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
	]))

func test_spawn_places_piece_at_default_origin() -> void:
	var p = Piece.spawn(PieceKind.Kind.T)
	assert_eq(p.kind, PieceKind.Kind.T)
	assert_eq(p.rot, PieceKind.Rot.ZERO)
	assert_eq(p.origin, Vector2i(PieceKind.SPAWN_COLS[PieceKind.Kind.T], PieceKind.SPAWN_ROW))

func test_piece_cells_apply_origin() -> void:
	var p = Piece.spawn(PieceKind.Kind.T)
	p.origin = Vector2i(3, 19)
	# T state 0 absolute cells.
	assert_eq(_sorted_cells(p.cells()), _sorted_cells([
		Vector2i(4, 19), Vector2i(3, 20), Vector2i(4, 20), Vector2i(5, 20),
	]))

func test_clone_is_independent() -> void:
	var p = Piece.spawn(PieceKind.Kind.J)
	var c = p.clone()
	c.origin = Vector2i(7, 5)
	c.rot = 2
	assert_eq(p.origin, Vector2i(PieceKind.SPAWN_COLS[PieceKind.Kind.J], PieceKind.SPAWN_ROW))
	assert_eq(p.rot, PieceKind.Rot.ZERO)
