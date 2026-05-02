class_name TetrisTSpin
extends RefCounted
## T-spin classification, isolated for testability.
##
## Called by GameState after every successful T rotation, with the resulting
## T-piece state, the kick index used (0..4), and the board *after* the
## rotation but *before* line clears. Returns one of:
##
##   NONE = 0   not a T-spin
##   MINI = 1   T-spin mini
##   FULL = 2   T-spin proper
##
## Rules (Tetris Guideline, "3-corner T-spin"):
##   * Pre-gate: at least 3 of the 4 corners of the T's 3x3 bounding box are
##     occupied by the playfield or are out-of-bounds.
##   * If 2 of the 2 "front" corners are occupied → FULL.
##     Otherwise → MINI.
##   * Kick #5 (last entry in the JLSTZ kick list, kick_index == 4) overrides
##     to FULL regardless of front/back, since reaching that kick already
##     requires a deeply enclosed T.
##
## "Front" corners are the two corners on the side the T points toward.

const PieceKind := preload("res://scripts/tetris/core/piece_kind.gd")
const Piece := preload("res://scripts/tetris/core/piece.gd")
const Board := preload("res://scripts/tetris/core/board.gd")

const NONE: int = 0
const MINI: int = 1
const FULL: int = 2

# All four corners of the 3x3 bounding box, in (col, row) offsets from origin.
const _CORNERS_NW: Vector2i = Vector2i(0, 0)
const _CORNERS_NE: Vector2i = Vector2i(2, 0)
const _CORNERS_SW: Vector2i = Vector2i(0, 2)
const _CORNERS_SE: Vector2i = Vector2i(2, 2)

# Per rotation, [front-corners], [back-corners].
# rot 0 = points up, R = right, 2 = down, L = left.
const _FRONT_BACK: Dictionary = {
	0: [[_CORNERS_NW, _CORNERS_NE], [_CORNERS_SW, _CORNERS_SE]],
	1: [[_CORNERS_NE, _CORNERS_SE], [_CORNERS_NW, _CORNERS_SW]],
	2: [[_CORNERS_SW, _CORNERS_SE], [_CORNERS_NW, _CORNERS_NE]],
	3: [[_CORNERS_NW, _CORNERS_SW], [_CORNERS_NE, _CORNERS_SE]],
}

static func classify(piece: Piece, kick_index: int, board: Board) -> int:
	if piece.kind != PieceKind.Kind.T:
		return NONE

	var fb: Array = _FRONT_BACK[piece.rot]
	var fronts: Array = fb[0]
	var backs: Array = fb[1]

	var front_filled: int = _count_blocked(piece.origin, fronts, board)
	var back_filled: int = _count_blocked(piece.origin, backs, board)
	var total: int = front_filled + back_filled
	if total < 3:
		return NONE

	# Kick-5 override (the last kick in the SRS JLSTZ table).
	if kick_index == 4:
		return FULL

	if front_filled == 2:
		return FULL
	return MINI

static func _count_blocked(origin: Vector2i, corner_offsets: Array, board: Board) -> int:
	var n: int = 0
	for off in corner_offsets:
		var col: int = origin.x + off.x
		var row: int = origin.y + off.y
		if board.is_blocked(col, row):
			n += 1
	return n
