extends RefCounted
## formation.gd — pure helpers for the invader formation. No state held;
## the caller (InvadersGameState) owns the live mask + origin and passes
## them in. No Node, no Engine APIs.
##
## Coordinate model:
##   - The formation has an origin (ox, oy) in world coords (top-left of
##     the grid's cell 0,0).
##   - Cell (col, row) center is at:
##         cx = ox + col * cell_w + cell_w * 0.5
##         cy = oy + row * cell_h + cell_h * 0.5
##   - Live mask is a flat PackedByteArray, length rows*cols, 1 = alive.
##
## The "reasoning" comments below explain why each helper exists, not what
## the code literally does — see the Dev plan in #27 for the full spec.


## Returns the (min_x_left, max_x_right) world bounds of all live cells in
## the formation (inclusive: min is left edge of leftmost alive, max is
## right edge of rightmost alive). Used to detect edge-bounce.
##
## Returns (-INF, -INF) if the formation has no live cells.
static func bounds_x(live_mask: PackedByteArray, rows: int, cols: int,
		ox: float, oy: float, cell_w: float, cell_h: float,
		enemy_hx: float) -> Vector2:
	var min_col: int = -1
	var max_col: int = -1
	for col in range(cols):
		var any_alive: bool = false
		for row in range(rows):
			if live_mask[row * cols + col] == 1:
				any_alive = true
				break
		if any_alive:
			if min_col == -1:
				min_col = col
			max_col = col
	if min_col == -1:
		return Vector2(-INF, -INF)
	# Each cell's center x then ± enemy_hx for edges.
	var lcx: float = ox + min_col * cell_w + cell_w * 0.5
	var rcx: float = ox + max_col * cell_w + cell_w * 0.5
	return Vector2(lcx - enemy_hx, rcx + enemy_hx)


## Returns the (min_y_top, max_y_bottom) of the formation. Used by the
## "any enemy crossed player line" loss check.
static func bounds_y(live_mask: PackedByteArray, rows: int, cols: int,
		ox: float, oy: float, cell_w: float, cell_h: float,
		enemy_hy: float) -> Vector2:
	var min_row: int = -1
	var max_row: int = -1
	for row in range(rows):
		var any_alive: bool = false
		for col in range(cols):
			if live_mask[row * cols + col] == 1:
				any_alive = true
				break
		if any_alive:
			if min_row == -1:
				min_row = row
			max_row = row
	if min_row == -1:
		return Vector2(-INF, -INF)
	var tcy: float = oy + min_row * cell_h + cell_h * 0.5
	var bcy: float = oy + max_row * cell_h + cell_h * 0.5
	return Vector2(tcy - enemy_hy, bcy + enemy_hy)


## Number of live enemies in the mask.
static func live_count(live_mask: PackedByteArray) -> int:
	var n: int = 0
	for i in range(live_mask.size()):
		if live_mask[i] == 1:
			n += 1
	return n


## Speed curve: linear lerp between min_step_ms (1 enemy left) and
## step_ms_init (full population).
##   step_ms = lerp(min_step_ms, step_ms_init, live / total)
## Documented in Dev plan §Algorithms — deliberate departure from arcade's
## piecewise-stepped table. A future config swap can restore arcade-faithful
## behaviour.
static func step_ms_for_population(live: int, total: int,
		step_ms_init: int, min_step_ms: int) -> int:
	if total <= 0:
		return min_step_ms
	var t: float = float(live) / float(total)
	t = clampf(t, 0.0, 1.0)
	var ms: float = lerpf(float(min_step_ms), float(step_ms_init), t)
	return int(round(ms))


## Find the column to fire from, given a uniform-random column index in
## [0, cols). If the chosen column has no live enemy, walks rightward
## until finding one. Returns -1 iff no live column exists.
static func find_firing_column(live_mask: PackedByteArray, rows: int, cols: int,
		seed_col: int) -> int:
	var c: int = seed_col % cols
	for _i in range(cols):
		for row in range(rows):
			if live_mask[row * cols + c] == 1:
				return c
		c = (c + 1) % cols
	return -1


## Bottom-most live row in `col`. Returns -1 if column is empty.
static func bottom_row(live_mask: PackedByteArray, rows: int, cols: int, col: int) -> int:
	for row in range(rows - 1, -1, -1):
		if live_mask[row * cols + col] == 1:
			return row
	return -1
