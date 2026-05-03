extends RefCounted
## Pure planner for 2048 moves. No state, no Node, no signals.
##
## Input: an id-grid (`Array[Array[Dictionary]]` where each cell is
## `{id: int, value: int}` with `id == 0` and `value == 0` for empty cells)
## plus a direction. Output: a MovePlan listing every tile that moves and
## any merges, plus the gained score. Plan is purely descriptive — applying
## it is the state's job (see g2048_state.gd).
##
## Algorithm:
##   1. Transform the id-grid into "merge LEFT" canonical form (same
##      transform logic as g2048_merge.transpose / reverse_row).
##   2. For each row, run g2048_merge.merge_row on the *value* projection.
##      That gives us per-row `sources` (which input columns landed where)
##      and per-row `merged_at` (whether each output cell was just merged).
##   3. Walk the per-row outputs to build TileMove records. For a slide
##      (1-source), emit one TileMove with merged_into = -1. For a merge
##      (2-source), pick the LATER source as the surviving tile (its id
##      lives on; the earlier source dies into it). The choice doesn't
##      affect rendering for symmetric tiles, but it must be consistent
##      so tests are deterministic — we pick the cell *closer to the move
##      direction* (i.e. the second source post-compaction) to match what
##      a human sees: the rear tile slides into the front tile.
##   4. Map canonical (canonical_r, canonical_c_out) back to grid (r, c)
##      via the inverse of the same transform.

const Self := preload("res://scripts/g2048/core/g2048_planner.gd")
const Merge := preload("res://scripts/g2048/core/g2048_merge.gd")

const DIR_LEFT: int = 0
const DIR_RIGHT: int = 1
const DIR_UP: int = 2
const DIR_DOWN: int = 3


class TileMove extends RefCounted:
	var id: int
	var from_cell: Vector2i
	var to_cell: Vector2i
	# id of the surviving tile this dying tile is merging into (-1 if no merge,
	# or if THIS tile is the survivor).
	var merged_into: int = -1
	# Value the tile carries at its destination. For survivors of a merge,
	# this is the doubled value. For sliders & dyers, the original value.
	var new_value: int = 0


class MovePlan extends RefCounted:
	var moves: Array = []  # Array[TileMove]
	var gained_score: int = 0
	func is_empty() -> bool:
		return moves.is_empty()


## Compute a MovePlan from the given id-grid and direction. Pure.
##
## `id_grid` is `Array[Array[Dictionary]]`, n×n, with cells `{id: int, value: int}`.
## Empty cells use `{id: 0, value: 0}`.
static func plan(id_grid: Array, dir: int) -> MovePlan:
	var n: int = id_grid.size()
	if n == 0:
		return MovePlan.new()

	# 1. Transform to canonical (merge-left) form. Track BOTH a value-only
	#    grid (for merge_row) and an id-only grid (to map output cols → ids).
	var canon_value: Array = []
	var canon_id: Array = []
	for r in n:
		var vrow: Array = []
		var irow: Array = []
		vrow.resize(n)
		irow.resize(n)
		for c in n:
			vrow[c] = int(id_grid[r][c]["value"])
			irow[c] = int(id_grid[r][c]["id"])
		canon_value.append(vrow)
		canon_id.append(irow)
	canon_value = _to_canonical(canon_value, dir)
	canon_id = _to_canonical(canon_id, dir)

	# 2. Per-row merge.
	var result: MovePlan = MovePlan.new()
	for r in n:
		var rowres: Dictionary = Merge.merge_row(canon_value[r])
		var sources: Array = rowres["sources"]
		var merged_at: Array = rowres["merged_at"]
		var out_row: Array = rowres["row"]
		result.gained_score += int(rowres["gained_score"])

		for out_c in sources.size():
			var srcs: Array = sources[out_c]
			if srcs.is_empty():
				continue  # padded zero
			if srcs.size() == 1:
				var src_c: int = int(srcs[0])
				if src_c == out_c:
					continue  # didn't move
				var move: TileMove = TileMove.new()
				move.id = int(canon_id[r][src_c])
				move.from_cell = _from_canonical(r, src_c, n, dir)
				move.to_cell = _from_canonical(r, out_c, n, dir)
				move.new_value = int(out_row[out_c])
				move.merged_into = -1
				result.moves.append(move)
			else:
				# srcs.size() == 2 — a merge. Pick survivor: the source closer
				# to the move direction, i.e. the second compacted source
				# (canonical merge slides toward index 0, so index `srcs[1]`
				# is the rear; the FRONT one wins). srcs[0] is the front in
				# canonical, srcs[1] is the rear, so the SURVIVOR is srcs[0].
				# Rationale: visually the rear tile slides into the front
				# tile, which doubles in place. Picking srcs[0] keeps the id
				# of the leading tile.
				var front_c: int = int(srcs[0])
				var rear_c: int = int(srcs[1])
				var survivor_id: int = int(canon_id[r][front_c])
				var dier_id: int = int(canon_id[r][rear_c])
				var doubled_value: int = int(out_row[out_c])

				# Survivor TileMove (slides front_c → out_c, value doubles).
				var sm: TileMove = TileMove.new()
				sm.id = survivor_id
				sm.from_cell = _from_canonical(r, front_c, n, dir)
				sm.to_cell = _from_canonical(r, out_c, n, dir)
				sm.new_value = doubled_value
				sm.merged_into = -1
				result.moves.append(sm)

				# Dier TileMove (slides rear_c → out_c, then disappears).
				var dm: TileMove = TileMove.new()
				dm.id = dier_id
				dm.from_cell = _from_canonical(r, rear_c, n, dir)
				dm.to_cell = _from_canonical(r, out_c, n, dir)
				dm.new_value = doubled_value / 2  # original pre-merge value
				dm.merged_into = survivor_id
				result.moves.append(dm)

				# merged_at is informational; not used in the plan output but
				# kept here as a sanity check during dev.
				assert(merged_at[out_c] == true, "sources size 2 but merged_at false")

	return result


# --- canonical-form transforms ---

# Given the original grid, return the "merge LEFT" canonical view for `dir`.
# Used for both value-grid and id-grid (same shape transforms apply).
static func _to_canonical(grid: Array, dir: int) -> Array:
	match dir:
		DIR_LEFT:
			return grid
		DIR_RIGHT:
			# reverse each row
			var out: Array = []
			for row in grid:
				out.append(Merge.reverse_row(row))
			return out
		DIR_UP:
			return Merge.transpose(grid)
		DIR_DOWN:
			# transpose, then reverse each row
			var t: Array = Merge.transpose(grid)
			var out2: Array = []
			for row in t:
				out2.append(Merge.reverse_row(row))
			return out2
		_:
			return grid


# Inverse of _to_canonical, applied to a single (canonical_r, canonical_c)
# pair. Returns the (r,c) Vector2i in the ORIGINAL grid coordinates.
static func _from_canonical(cr: int, cc: int, n: int, dir: int) -> Vector2i:
	match dir:
		DIR_LEFT:
			# canonical (cr, cc) = original (cr, cc)
			return Vector2i(cc, cr)
		DIR_RIGHT:
			# canonical (cr, cc) = original (cr, n-1-cc)
			return Vector2i(n - 1 - cc, cr)
		DIR_UP:
			# transpose: canonical[r][c] = original[c][r]; so canonical (cr,cc) = original (cc, cr).
			return Vector2i(cr, cc)
		DIR_DOWN:
			# transpose then reverse: canonical[r][c] = original[n-1-c][r]
			# (transpose maps original[r][c] to T[c][r]; reverse_row on T[c]
			# maps T[c][k] = original[k][c] to canonical[c][n-1-k]. So
			# canonical[c][n-1-k] = original[k][c]; i.e. canonical (cr, cc) =
			# original (n-1-cc, cr).)
			return Vector2i(cr, n - 1 - cc)
		_:
			return Vector2i(cc, cr)
