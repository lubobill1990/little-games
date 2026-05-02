class_name TetrisPiece
extends RefCounted
## Live tetromino state: kind + origin (col, row in 10x40 board space) + rotation.
## Pure value object. Rendering is a downstream concern.

const PieceKind := preload("res://scripts/tetris/core/piece_kind.gd")

var kind: int = PieceKind.Kind.I
var origin: Vector2i = Vector2i.ZERO
var rot: int = PieceKind.Rot.ZERO

static func spawn(kind_id: int) -> TetrisPiece:
	var p: TetrisPiece = TetrisPiece.new()
	p.kind = kind_id
	p.origin = Vector2i(PieceKind.SPAWN_COLS[kind_id], PieceKind.SPAWN_ROW)
	p.rot = PieceKind.Rot.ZERO
	return p

func clone() -> TetrisPiece:
	var p: TetrisPiece = TetrisPiece.new()
	p.kind = kind
	p.origin = origin
	p.rot = rot
	return p

## Absolute board cells occupied by this piece in its current orientation.
func cells() -> Array:
	var out: Array = []
	for off in PieceKind.cells(kind, rot):
		out.append(origin + off)
	return out

## Cells the piece would occupy at a given (origin, rot) without mutating self.
func cells_at(at_origin: Vector2i, at_rot: int) -> Array:
	var out: Array = []
	for off in PieceKind.cells(kind, at_rot):
		out.append(at_origin + off)
	return out
