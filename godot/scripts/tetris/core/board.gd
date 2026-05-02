class_name TetrisBoard
extends RefCounted
## 10x40 playfield grid (cols 0..9, rows 0..39). Pure data + queries.
##
## Row layout: rows 0..19 are the buffer above the visible field; rows 20..39
## are the 20 visible playfield rows. y grows downward (Godot screen space),
## so the floor is row 39. Cell value 0 = empty, 1..7 = TetrisPieceKind enum.
##
## Mutations are limited to:
##   - lock_piece(piece)       writes piece cells into the grid
##   - clear_full_rows()       removes complete rows, gravity drops above (naive)
##   - set_cell(col, row, k)   for testing/snapshot restore
## Everything else is a query. No Node, no Engine, no autoloads.

const PieceKind := preload("res://scripts/tetris/core/piece_kind.gd")
const Piece := preload("res://scripts/tetris/core/piece.gd")

const COLS: int = 10
const ROWS: int = 40
const VISIBLE_TOP: int = 20  # First visible row (rows VISIBLE_TOP..ROWS-1 are on-screen).

var cells: PackedInt32Array

func _init() -> void:
	cells = PackedInt32Array()
	cells.resize(COLS * ROWS)
	# PackedInt32Array.resize() zero-fills, so no explicit clear needed.

static func idx(col: int, row: int) -> int:
	return col + row * COLS

func in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < COLS and row >= 0 and row < ROWS

func get_cell(col: int, row: int) -> int:
	if not in_bounds(col, row):
		return -1
	return cells[idx(col, row)]

func set_cell(col: int, row: int, kind: int) -> void:
	if in_bounds(col, row):
		cells[idx(col, row)] = kind

## True if the given absolute cell is filled OR out of bounds. The buffer above
## row 0 is treated as out-of-bounds (top wall), but in practice spawns occur
## in the buffer so callers should query cells inside [0, ROWS).
func is_blocked(col: int, row: int) -> bool:
	if col < 0 or col >= COLS or row >= ROWS:
		return true
	if row < 0:
		# Buffer above index 0 is allowed (a piece can rotate into negative rows
		# during spawn-state rotations, but only the cells inside the grid count).
		return false
	return cells[idx(col, row)] != 0

## True if every cell of `piece` at (origin, rot) is unoccupied and in-bounds.
func can_place(piece: Piece, at_origin: Vector2i, at_rot: int) -> bool:
	for c in piece.cells_at(at_origin, at_rot):
		if is_blocked(c.x, c.y):
			return false
		# Stricter: piece must be in-bounds horizontally and not below floor.
		if c.x < 0 or c.x >= COLS or c.y >= ROWS:
			return false
	return true

## Writes piece cells. Caller is responsible for having checked can_place().
func lock_piece(piece: Piece) -> void:
	for c in piece.cells():
		if c.y >= 0 and c.y < ROWS and c.x >= 0 and c.x < COLS:
			cells[idx(c.x, c.y)] = piece.kind

## Returns row indices (0..ROWS-1) that are completely filled.
func full_rows() -> Array:
	var out: Array = []
	for r in range(ROWS):
		var full: bool = true
		for c in range(COLS):
			if cells[idx(c, r)] == 0:
				full = false
				break
		if full:
			out.append(r)
	return out

## Removes the given rows and shifts everything above downward (naive gravity).
## Returns the count of cleared rows.
func clear_rows(rows: Array) -> int:
	if rows.is_empty():
		return 0
	# Sort ascending so we can shift in one pass top-down.
	var sorted_rows: Array = rows.duplicate()
	sorted_rows.sort()
	# Build a new grid by walking rows bottom-to-top, skipping cleared ones,
	# and stacking surviving rows from the bottom.
	var new_cells: PackedInt32Array = PackedInt32Array()
	new_cells.resize(COLS * ROWS)
	var write_row: int = ROWS - 1
	var clear_set: Dictionary = {}
	for r in sorted_rows:
		clear_set[r] = true
	for r in range(ROWS - 1, -1, -1):
		if clear_set.has(r):
			continue
		for c in range(COLS):
			new_cells[idx(c, write_row)] = cells[idx(c, r)]
		write_row -= 1
	cells = new_cells
	return sorted_rows.size()

## Convenience: lock + clear in one pass; returns rows cleared.
func clear_full_rows() -> int:
	return clear_rows(full_rows())

## Reset to all-empty.
func reset() -> void:
	for i in range(cells.size()):
		cells[i] = 0

func snapshot() -> PackedInt32Array:
	return cells.duplicate()

func restore(snap: PackedInt32Array) -> void:
	cells = snap.duplicate()
