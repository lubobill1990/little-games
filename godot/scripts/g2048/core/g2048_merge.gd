extends RefCounted
## Pure merge / grid-transform helpers for 2048.
##
## A "row" here is `Array[int]` of cell **values** (0 = empty). Row math is
## intentionally value-only — id-aware planning lives in g2048_planner.gd
## which calls these as building blocks.
##
## All four directions are implemented by transforming the grid into the
## "merge LEFT" canonical form, running merge_row, then transforming back.
## Pattern table (let `[r,c]` be a cell, `n = size - 1`):
##
##   LEFT:  identity                          (then row in-place merge_row)
##   RIGHT: reverse each row                  (merge_row, reverse back)
##   UP:    transpose                         (merge_row per row, transpose back)
##   DOWN:  transpose + reverse each row      (merge_row, reverse, transpose)

const Self := preload("res://scripts/g2048/core/g2048_merge.gd")


## Slide-and-merge a single row LEFT. Returns
##   { "row": Array[int], "gained_score": int, "merged_at": Array[bool] }
##
## - `row` is the resulting row (zeros padded right to original length).
## - `gained_score` is the sum of merged-cell values (e.g. 2+2 → +4).
## - `merged_at[i]` is true iff the cell at output index `i` was just born from
##   a merge this step. Planner uses this to figure out which two source tiles
##   collapsed into which destination index.
static func merge_row(row: Array) -> Dictionary:
	var n: int = row.size()
	# 1. Compact: drop zeros, preserving order. Track each surviving cell's
	#    ORIGINAL index so the planner can map output positions to source cells.
	var compact: Array = []
	var src_idx: Array = []
	for i in n:
		var v: int = int(row[i])
		if v != 0:
			compact.append(v)
			src_idx.append(i)
	# 2. Walk left-to-right, merge equal neighbours; locked-after-merge prevents
	#    chaining (4,4,8 must NOT become 16, only 8,8 → kept distinct).
	var out_vals: Array = []
	var out_merged: Array = []
	# For planner consumption: for each output slot, the list of *source row
	# indices* that landed there (1 element if just slide, 2 if merge).
	var out_sources: Array = []
	var gained: int = 0
	var i: int = 0
	while i < compact.size():
		if i + 1 < compact.size() and compact[i] == compact[i + 1]:
			var v: int = int(compact[i])
			out_vals.append(v * 2)
			out_merged.append(true)
			out_sources.append([src_idx[i], src_idx[i + 1]])
			gained += v * 2
			i += 2
		else:
			out_vals.append(int(compact[i]))
			out_merged.append(false)
			out_sources.append([src_idx[i]])
			i += 1
	# 3. Right-pad with zeros.
	while out_vals.size() < n:
		out_vals.append(0)
		out_merged.append(false)
		out_sources.append([])
	return {
		"row": out_vals,
		"merged_at": out_merged,
		"sources": out_sources,
		"gained_score": gained,
	}


## Reverse a row in place semantics; returns a new Array[int].
static func reverse_row(row: Array) -> Array:
	var n: int = row.size()
	var out: Array = []
	out.resize(n)
	for i in n:
		out[i] = row[n - 1 - i]
	return out


## Transpose an n×n grid (Array of Array). Returns new grid.
static func transpose(grid: Array) -> Array:
	var n: int = grid.size()
	var out: Array = []
	for r in n:
		var row: Array = []
		row.resize(n)
		out.append(row)
	for r in n:
		for c in n:
			out[c][r] = grid[r][c]
	return out
