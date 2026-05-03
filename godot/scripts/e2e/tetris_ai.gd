extends RefCounted
## Heuristic Tetris agent — Pierre Dellacherie style. Pure GDScript. Reads a
## tetris/core snapshot, picks the best lock placement for the current piece,
## emits an ordered action plan to reach that placement, and feeds the actions
## one per frame to the caller.
##
## **No Node, no Godot autoloads.** The runner is the only thing that touches
## the engine; this class operates on plain values and a TetrisGameState
## reference (RefCounted, no scene tree).
##
## Design notes:
## - Plan-then-execute: when a new piece spawns, search every (rot, col) drop
##   placement, score it by the heuristic, pick the best. Then issue actions
##   (rotate / move / hard_drop) one per `next_action()` call until the plan
##   is exhausted. This avoids re-planning every frame and keeps the action
##   log small and human-readable.
## - We use the live `tetris/core` for placement validation by **simulating
##   on a clone of the board** (not via SRS kicks — pure drop-from-top). This
##   is approximate (ignores T-spins, soft-drop tucks) but matches the user
##   experience the AI is meant to mimic ("a player who plays Tetris well").
## - Heuristic = weighted sum of:
##     -0.51 * aggregate_height
##     +0.76 * lines_cleared
##     -0.36 * holes
##     -0.18 * bumpiness
##   Weights from the Dellacherie classic tuning. Sign convention: more-is-better.
##
## Determinism: pure function over (board, current_kind, current_rot). Floats
## are deterministic GDScript doubles; same input = same output.

const Self := preload("res://scripts/e2e/tetris_ai.gd")
const Board := preload("res://scripts/tetris/core/board.gd")
const PieceKind := preload("res://scripts/tetris/core/piece_kind.gd")
const Piece := preload("res://scripts/tetris/core/piece.gd")
const TetrisGameState := preload("res://scripts/tetris/core/game_state.gd")

# Dellacherie defaults (well-known starting weights). Tunable later — keep them
# in one place so video review can iterate without grepping the codebase.
const W_AGG_HEIGHT: float = -0.510066
const W_LINES_CLEARED: float = 0.760666
const W_HOLES: float = -0.35663
const W_BUMPINESS: float = -0.184483

# Action codes emitted by the planner. Strings (not enums) so the action log
# in the JSON sidecar stays human-readable and grep-friendly.
const ACT_ROTATE_CW: StringName = &"rotate_cw"
const ACT_MOVE_LEFT: StringName = &"move_left"
const ACT_MOVE_RIGHT: StringName = &"move_right"
const ACT_HARD_DROP: StringName = &"hard_drop"

# State per piece: the planned action queue. Empty means "compute a new plan".
var _plan: Array[StringName] = []
# Kind of the piece the current plan was built for; if it changes (next piece
# spawned, piece swapped via hold) we replan.
var _planned_for_kind: int = -1
var _planned_for_origin_y: int = -1

# --- Public API ---


## Pick the next action given the live game state. Returns one of the ACT_*
## constants, or empty StringName when nothing should be done this frame
## (game over, no piece, plan exhausted but piece hasn't spawned yet).
func next_action(state: TetrisGameState) -> StringName:
	if state == null or state.is_game_over():
		return &""
	var piece: Piece = state.current_piece()
	if piece == null:
		return &""
	# Replan when the piece kind changes (new spawn or hold swap). We also
	# replan if the origin Y reset (means a fresh spawn of the same kind).
	if piece.kind != _planned_for_kind or piece.origin.y != _planned_for_origin_y or _plan.is_empty():
		_plan = _plan_for(state)
		_planned_for_kind = piece.kind
		_planned_for_origin_y = piece.origin.y
	if _plan.is_empty():
		# Defensive: planner couldn't find any placement (shouldn't happen on a
		# legal board). Fall back to hard drop so we make progress.
		return ACT_HARD_DROP
	return _plan.pop_front()


## Reset planner state. Call when the game restarts so we don't apply stale
## plans against a fresh piece that happens to share kind+origin.
func reset() -> void:
	_plan = []
	_planned_for_kind = -1
	_planned_for_origin_y = -1


# --- Heuristic scoring (pure; tested directly) ---


## Score a candidate post-lock board using the Dellacherie weighted sum. Higher
## is better. The 4 features are documented above; this function is the unit
## under test.
static func score_board(cells: PackedInt32Array, lines_cleared: int) -> float:
	var heights: PackedInt32Array = column_heights(cells)
	var agg: int = 0
	for h in heights:
		agg += h
	var bump: int = 0
	for c in range(Board.COLS - 1):
		bump += absi(heights[c] - heights[c + 1])
	var holes: int = count_holes(cells, heights)
	return (W_AGG_HEIGHT * float(agg)
			+ W_LINES_CLEARED * float(lines_cleared)
			+ W_HOLES * float(holes)
			+ W_BUMPINESS * float(bump))


## Per-column height: ROWS - first_filled_row, or 0 if column entirely empty.
## Heights are measured from the bottom (row ROWS-1 = floor).
static func column_heights(cells: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(Board.COLS)
	for col in range(Board.COLS):
		var h: int = 0
		for row in range(Board.ROWS):
			if cells[Board.idx(col, row)] != 0:
				h = Board.ROWS - row
				break
		out[col] = h
	return out


## Holes = empty cells with at least one filled cell directly above them in the
## same column. The classic Dellacherie definition.
static func count_holes(cells: PackedInt32Array, heights: PackedInt32Array) -> int:
	var n: int = 0
	for col in range(Board.COLS):
		var h: int = heights[col]
		if h <= 1:
			continue
		# Top filled row in this column is at row = ROWS - h. Walk down from
		# there to the floor and count empty cells.
		var top_row: int = Board.ROWS - h
		for row in range(top_row + 1, Board.ROWS):
			if cells[Board.idx(col, row)] == 0:
				n += 1
	return n


# --- Planner ---


# Search every (rot, col) drop placement for `state.piece` and pick the one
# that maximizes score_board(post_lock_cells, lines_cleared). Returns the
# action sequence (rotate_cw* + move_left/right* + hard_drop) needed to
# reach it.
func _plan_for(state: TetrisGameState) -> Array[StringName]:
	var piece: Piece = state.current_piece()
	if piece == null:
		return []
	var best_score: float = -INF
	var best_rot: int = piece.rot
	var best_col: int = piece.origin.x
	var board: Board = state.board
	var snap: PackedInt32Array = board.cells.duplicate()
	# Try all 4 rotations (O has 4 identical, harmless).
	for rot in range(4):
		# For each rotation, scan every legal x position (origin column) and
		# drop straight down. Use cells_at to skip illegal lateral positions
		# without touching the live piece.
		for col in range(-3, Board.COLS + 3):
			var origin: Vector2i = Vector2i(col, piece.origin.y)
			# Skip if the start position is illegal (e.g. piece partly out
			# of bounds). We scan a wider range than COLS because piece bbox
			# offsets can be 0..3 wide.
			if not board.can_place(piece, origin, rot):
				continue
			# Drop straight down to the lowest legal row.
			var drop_y: int = origin.y
			while board.can_place(piece, Vector2i(col, drop_y + 1), rot):
				drop_y += 1
			# Simulate the lock on a fresh copy.
			var sim: PackedInt32Array = snap.duplicate()
			for off in PieceKind.cells(piece.kind, rot):
				var cx: int = col + off.x
				var cy: int = drop_y + off.y
				if cx >= 0 and cx < Board.COLS and cy >= 0 and cy < Board.ROWS:
					sim[Board.idx(cx, cy)] = piece.kind
			# Count + clear full rows on the simulated grid (mirrors Board.clear_rows).
			var cleared: int = _simulate_clear(sim)
			var s: float = score_board(sim, cleared)
			if s > best_score:
				best_score = s
				best_rot = rot
				best_col = col
	# Build the action sequence. Rotate first, then translate, then hard drop.
	# Use minimum CW rotations (3 CW = 1 CCW; we only emit CW for log simplicity).
	var actions: Array[StringName] = []
	var r: int = piece.rot
	var rotations_needed: int = (best_rot - r + 4) % 4
	for _i in rotations_needed:
		actions.append(ACT_ROTATE_CW)
	var dx: int = best_col - piece.origin.x
	if dx < 0:
		for _i in (-dx):
			actions.append(ACT_MOVE_LEFT)
	elif dx > 0:
		for _i in dx:
			actions.append(ACT_MOVE_RIGHT)
	actions.append(ACT_HARD_DROP)
	return actions


## Mutates `cells` in place: removes full rows, shifts above downward.
## Returns the count cleared. Mirrors Board.clear_rows logic; duplicated here
## so the AI can plan against a simulated grid without touching live state.
static func _simulate_clear(cells: PackedInt32Array) -> int:
	var clear_set: Dictionary = {}
	for r in range(Board.ROWS):
		var full: bool = true
		for c in range(Board.COLS):
			if cells[Board.idx(c, r)] == 0:
				full = false
				break
		if full:
			clear_set[r] = true
	if clear_set.is_empty():
		return 0
	var write_row: int = Board.ROWS - 1
	var new_cells: PackedInt32Array = PackedInt32Array()
	new_cells.resize(Board.COLS * Board.ROWS)
	for r in range(Board.ROWS - 1, -1, -1):
		if clear_set.has(r):
			continue
		for c in range(Board.COLS):
			new_cells[Board.idx(c, write_row)] = cells[Board.idx(c, r)]
		write_row -= 1
	# Copy back.
	for i in range(cells.size()):
		cells[i] = new_cells[i]
	return clear_set.size()
