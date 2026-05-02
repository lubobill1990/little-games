extends GutTest
## Verifies SRS kick table contents against the Tetris Guideline.
##
## We don't simulate boards here — that's the kicks' job inside Board/GameState.
## What we lock in is the *table itself* (5 offsets per transition, exact values
## copied from the wiki), so a typo in a constant is caught immediately.
## Coordinate note: SRS publishes y-up. We store y-down (Godot screen). Each
## "y" below is the negation of the wiki value.

const PieceKind := preload("res://scripts/tetris/core/piece_kind.gd")
const Kicks := preload("res://scripts/tetris/core/kicks.gd")

const _JLSTZ_KINDS: Array = [
	PieceKind.Kind.J, PieceKind.Kind.L, PieceKind.Kind.S, PieceKind.Kind.T, PieceKind.Kind.Z
]
const _ALL_TRANSITIONS: Array = [
	[0, 1], [1, 0], [1, 2], [2, 1], [2, 3], [3, 2], [3, 0], [0, 3]
]

func test_key_encodes_uniquely() -> void:
	var seen: Dictionary = {}
	for t in _ALL_TRANSITIONS:
		var k = Kicks.key(t[0], t[1])
		assert_false(seen.has(k), "key collision %d->%d" % t)
		seen[k] = true
	assert_eq(seen.size(), 8)

func test_every_transition_has_five_offsets_for_jlstz() -> void:
	for kind in _JLSTZ_KINDS:
		for t in _ALL_TRANSITIONS:
			var off = Kicks.offsets(kind, t[0], t[1])
			assert_eq(off.size(), 5, "kind=%d %d->%d" % [kind, t[0], t[1]])

func test_every_transition_has_five_offsets_for_i() -> void:
	for t in _ALL_TRANSITIONS:
		var off = Kicks.offsets(PieceKind.Kind.I, t[0], t[1])
		assert_eq(off.size(), 5, "I %d->%d" % [t[0], t[1]])

func test_first_attempt_is_always_no_kick() -> void:
	for kind in PieceKind.KINDS:
		if kind == PieceKind.Kind.O:
			continue
		for t in _ALL_TRANSITIONS:
			assert_eq(Kicks.offsets(kind, t[0], t[1])[0], Vector2i.ZERO,
					"first kick must be (0,0) for kind=%d %d->%d" % [kind, t[0], t[1]])

func test_o_piece_never_kicks() -> void:
	for t in _ALL_TRANSITIONS:
		var off = Kicks.offsets(PieceKind.Kind.O, t[0], t[1])
		assert_eq(off, [Vector2i.ZERO], "O kicks should be (0,0) only, got %s" % str(off))

# --- Spot checks against the Guideline tables (y-flipped from the wiki). ---

func test_jlstz_zero_to_r_offsets() -> void:
	# Wiki: ( 0, 0), (-1, 0), (-1,+1), ( 0,-2), (-1,-2)  (y-up)
	# Ours: ( 0, 0), (-1, 0), (-1,-1), ( 0,+2), (-1,+2)  (y-down)
	assert_eq(Kicks.offsets(PieceKind.Kind.T, 0, 1), [
		Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, 2), Vector2i(-1, 2),
	])

func test_jlstz_r_to_zero_offsets() -> void:
	# Wiki: (0,0),(+1,0),(+1,-1),(0,+2),(+1,+2)
	assert_eq(Kicks.offsets(PieceKind.Kind.J, 1, 0), [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, -2), Vector2i(1, -2),
	])

func test_jlstz_two_to_l_offsets() -> void:
	# Wiki: (0,0),(+1,0),(+1,+1),(0,-2),(+1,-2)
	assert_eq(Kicks.offsets(PieceKind.Kind.L, 2, 3), [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, 2), Vector2i(1, 2),
	])

func test_jlstz_zero_to_l_offsets() -> void:
	# Wiki: (0,0),(+1,0),(+1,+1),(0,-2),(+1,-2)
	assert_eq(Kicks.offsets(PieceKind.Kind.S, 0, 3), [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, 2), Vector2i(1, 2),
	])

func test_i_zero_to_r_offsets() -> void:
	# Wiki: (0,0),(-2,0),(+1,0),(-2,-1),(+1,+2)
	assert_eq(Kicks.offsets(PieceKind.Kind.I, 0, 1), [
		Vector2i(0, 0), Vector2i(-2, 0), Vector2i(1, 0), Vector2i(-2, 1), Vector2i(1, -2),
	])

func test_i_r_to_two_offsets() -> void:
	# Wiki: (0,0),(-1,0),(+2,0),(-1,+2),(+2,-1)
	assert_eq(Kicks.offsets(PieceKind.Kind.I, 1, 2), [
		Vector2i(0, 0), Vector2i(-1, 0), Vector2i(2, 0), Vector2i(-1, -2), Vector2i(2, 1),
	])

func test_i_two_to_l_offsets() -> void:
	# Wiki: (0,0),(+2,0),(-1,0),(+2,+1),(-1,-2)
	assert_eq(Kicks.offsets(PieceKind.Kind.I, 2, 3), [
		Vector2i(0, 0), Vector2i(2, 0), Vector2i(-1, 0), Vector2i(2, -1), Vector2i(-1, 2),
	])

func test_i_l_to_zero_offsets() -> void:
	# Wiki: (0,0),(+1,0),(-2,0),(+1,-2),(-2,+1)
	assert_eq(Kicks.offsets(PieceKind.Kind.I, 3, 0), [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(-2, 0), Vector2i(1, 2), Vector2i(-2, -1),
	])

func test_jlstz_kicks_are_uniform_across_kinds() -> void:
	# JLSTZ share the table; T must equal J, L, S, Z for every transition.
	for t in _ALL_TRANSITIONS:
		var ref = Kicks.offsets(PieceKind.Kind.T, t[0], t[1])
		for kind in [PieceKind.Kind.J, PieceKind.Kind.L, PieceKind.Kind.S, PieceKind.Kind.Z]:
			assert_eq(Kicks.offsets(kind, t[0], t[1]), ref,
					"kind=%d %d->%d diverges from T" % [kind, t[0], t[1]])
