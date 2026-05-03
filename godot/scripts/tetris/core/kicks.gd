extends RefCounted
## SRS wall-kick offset tables. Pure data — no Node, no Engine.
##
## Each entry maps a rotation transition (e.g. "0->R") to an Array of 5 offsets
## tried in order; the first one whose translated/rotated piece doesn't collide
## wins. The (0, 0) "no kick" attempt is included as the first offset per the
## Guideline. Coordinate convention: +x = right, +y = down (Godot screen space),
## so SRS's "+y up" rows have their y signs negated below.
##
## Source: https://tetris.wiki/Super_Rotation_System (JLSTZ + I-piece tables).
## O-piece never kicks (it's rotation-invariant).

const PieceKind := preload("res://scripts/tetris/core/piece_kind.gd")

# Transition keys. Use ints to avoid string-key allocation in hot paths.
# Encoded as (from * 4 + to). Only the 8 legal transitions are populated.
static func key(from_rot: int, to_rot: int) -> int:
	return from_rot * 4 + to_rot

const _JLSTZ: Dictionary = {
	# 0 -> R
	0 * 4 + 1: [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, 2), Vector2i(-1, 2)],
	# R -> 0
	1 * 4 + 0: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, -2), Vector2i(1, -2)],
	# R -> 2
	1 * 4 + 2: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, -2), Vector2i(1, -2)],
	# 2 -> R
	2 * 4 + 1: [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, 2), Vector2i(-1, 2)],
	# 2 -> L
	2 * 4 + 3: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, 2), Vector2i(1, 2)],
	# L -> 2
	3 * 4 + 2: [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -2), Vector2i(-1, -2)],
	# L -> 0
	3 * 4 + 0: [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -2), Vector2i(-1, -2)],
	# 0 -> L
	0 * 4 + 3: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, 2), Vector2i(1, 2)],
}

const _I: Dictionary = {
	# 0 -> R
	0 * 4 + 1: [Vector2i(0, 0), Vector2i(-2, 0), Vector2i(1, 0), Vector2i(-2, 1), Vector2i(1, -2)],
	# R -> 0
	1 * 4 + 0: [Vector2i(0, 0), Vector2i(2, 0), Vector2i(-1, 0), Vector2i(2, -1), Vector2i(-1, 2)],
	# R -> 2
	1 * 4 + 2: [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(2, 0), Vector2i(-1, -2), Vector2i(2, 1)],
	# 2 -> R
	2 * 4 + 1: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-2, 0), Vector2i(1, 2), Vector2i(-2, -1)],
	# 2 -> L
	2 * 4 + 3: [Vector2i(0, 0), Vector2i(2, 0), Vector2i(-1, 0), Vector2i(2, -1), Vector2i(-1, 2)],
	# L -> 2
	3 * 4 + 2: [Vector2i(0, 0), Vector2i(-2, 0), Vector2i(1, 0), Vector2i(-2, 1), Vector2i(1, -2)],
	# L -> 0
	3 * 4 + 0: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-2, 0), Vector2i(1, 2), Vector2i(-2, -1)],
	# 0 -> L
	0 * 4 + 3: [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(2, 0), Vector2i(-1, -2), Vector2i(2, 1)],
}

## Returns the 5 kick offsets (first is always (0,0)) for the given piece kind
## and rotation transition. O-piece returns a single (0,0) entry — it never kicks.
static func offsets(kind: int, from_rot: int, to_rot: int) -> Array:
	if kind == PieceKind.Kind.O:
		return [Vector2i.ZERO]
	if kind == PieceKind.Kind.I:
		return _I[key(from_rot, to_rot)]
	return _JLSTZ[key(from_rot, to_rot)]
