extends RefCounted
## SRS piece kinds and per-rotation cell layouts. Pure data — no Node, no Engine.
##
## Cells are Vector2i(col, row) offsets relative to the piece's origin (its
## bounding-box top-left, in board coords with y-down). Rotation states cycle
## 0 → R → 2 → L (clockwise). Layouts copied verbatim from the Tetris Guideline
## SRS spec; see https://tetris.wiki/Super_Rotation_System.

enum Kind { I = 1, O = 2, T = 3, S = 4, Z = 5, J = 6, L = 7 }
enum Rot { ZERO = 0, R = 1, TWO = 2, L = 3 }

const KINDS: Array = [Kind.I, Kind.O, Kind.T, Kind.S, Kind.Z, Kind.J, Kind.L]

# Per-kind, per-rotation cell offsets. Indexed [kind][rot] -> Array[Vector2i].
const SHAPES: Dictionary = {
	Kind.I: [
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)],
		[Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)],
		[Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)],
	],
	Kind.O: [
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
	],
	Kind.T: [
		[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
		[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)],
	],
	Kind.S: [
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)],
		[Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2)],
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)],
	],
	Kind.Z: [
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)],
		[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)],
	],
	Kind.J: [
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(1, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)],
	],
	Kind.L: [
		[Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2)],
	],
}

# Spawn column (origin x) per kind. I & O get explicit centering per Guideline.
# Spawn row (origin y) is row 19 — top of buffer means cells render in rows
# 19..22 of the 40-row grid (rows 20+ are visible playfield-from-top).
const SPAWN_COLS: Dictionary = {
	Kind.I: 3, Kind.O: 3, Kind.T: 3, Kind.S: 3, Kind.Z: 3, Kind.J: 3, Kind.L: 3,
}
const SPAWN_ROW: int = 19

static func cells(kind: int, rot: int) -> Array:
	return SHAPES[kind][rot]

static func rotate_cw(rot: int) -> int:
	return (rot + 1) % 4

static func rotate_ccw(rot: int) -> int:
	return (rot + 3) % 4
