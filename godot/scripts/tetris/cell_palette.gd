class_name TetrisCellPalette
extends RefCounted
## Per-piece-kind cell color. Used by playfield, ghost, hold slot, next queue.

const PieceKind := preload("res://scripts/tetris/core/piece_kind.gd")

const EMPTY: Color = Color(0.08, 0.08, 0.10, 1.0)
const GRID_LINE: Color = Color(1, 1, 1, 0.06)
const BORDER: Color = Color(0.6, 0.6, 0.7, 0.8)
const GHOST_ALPHA: float = 0.28

const _COLORS: Dictionary = {
	PieceKind.Kind.I: Color(0.31, 0.78, 0.91, 1.0),
	PieceKind.Kind.O: Color(0.95, 0.85, 0.25, 1.0),
	PieceKind.Kind.T: Color(0.66, 0.34, 0.85, 1.0),
	PieceKind.Kind.S: Color(0.36, 0.81, 0.42, 1.0),
	PieceKind.Kind.Z: Color(0.91, 0.34, 0.36, 1.0),
	PieceKind.Kind.J: Color(0.27, 0.43, 0.92, 1.0),
	PieceKind.Kind.L: Color(0.92, 0.55, 0.20, 1.0),
}

static func color_for(kind: int) -> Color:
	if _COLORS.has(kind):
		return _COLORS[kind]
	return EMPTY

static func ghost_color(kind: int) -> Color:
	var c: Color = color_for(kind)
	c.a = GHOST_ALPHA
	return c
