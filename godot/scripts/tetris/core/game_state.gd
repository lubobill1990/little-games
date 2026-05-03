extends RefCounted
## The pure Tetris controller: composes Board, Bag, Scoring, T-spin into a
## tickable rule machine. No Node, no Engine, no autoloads — caller drives
## time via tick(now_ms) and feeds inputs via move/rotate/soft_drop/hard_drop/hold.
##
## All randomness is seeded through TetrisBag. Same seed + same input timeline
## reproduces the same snapshot exactly — that's the property #7 (integration
## tests) relies on.

const Self := preload("res://scripts/tetris/core/game_state.gd")
const PieceKind := preload("res://scripts/tetris/core/piece_kind.gd")
const Piece := preload("res://scripts/tetris/core/piece.gd")
const Board := preload("res://scripts/tetris/core/board.gd")
const Bag := preload("res://scripts/tetris/core/bag.gd")
const Kicks := preload("res://scripts/tetris/core/kicks.gd")
const TSpin := preload("res://scripts/tetris/core/t_spin.gd")
const Scoring := preload("res://scripts/tetris/core/scoring.gd")
const Levels := preload("res://scripts/tetris/core/levels.gd")

signal piece_locked(result: Dictionary)
signal game_over(reason: int)

# Game-over reason codes.
const REASON_BLOCK_OUT: int = 1
const REASON_LOCK_OUT: int = 2
const REASON_TOP_OUT: int = 3

# Lock-delay knobs (Tetris Guideline "infinity" prevention).
const LOCK_DELAY_MS: int = 500
const LOCK_RESET_CAP: int = 15

var board: Board
var bag: Bag
var scoring: Scoring

var piece: Piece               # null if game over before respawn
var held_kind: int = -1        # -1 = nothing held
var hold_used: bool = false
var _game_over: bool = false
var _last_kick_index: int = -1 # kick used by most recent rotate; consumed only by T-spin classification on lock

# Time / gravity bookkeeping.
var _last_tick_ms: int = -1
var _gravity_ms_owed: int = 0  # accumulator; spends ms_per_row to drop one cell
var _soft_drop_ms_owed: int = 0  # accumulator for held-down soft-drop rate limiting

# Lock-delay bookkeeping. _is_grounded means piece is resting on something.
var _is_grounded: bool = false
var _lock_ms_owed: int = 0
var _lock_resets: int = 0

static func create(game_seed: int) -> Self:
	var g: Self = Self.new()
	g.board = Board.new()
	g.bag = Bag.create(game_seed)
	g.scoring = Scoring.new()
	g._spawn_next()
	return g

# --- Public API ---

func tick(now_ms: int) -> void:
	if _game_over or piece == null:
		_last_tick_ms = now_ms
		return
	if _last_tick_ms < 0:
		_last_tick_ms = now_ms
		return
	var dt: int = max(0, now_ms - _last_tick_ms)
	_last_tick_ms = now_ms
	_advance_gravity(dt)
	_advance_lock_delay(dt)

func move(dx: int) -> Dictionary:
	if _game_over or piece == null or dx == 0:
		return {"success": false, "kick_index": -1}
	var new_origin = piece.origin + Vector2i(dx, 0)
	if board.can_place(piece, new_origin, piece.rot):
		piece.origin = new_origin
		_on_successful_move()
		return {"success": true, "kick_index": -1}
	return {"success": false, "kick_index": -1}

## Rotate by +1 (CW) or -1 (CCW). Tries SRS kicks in order. Returns
## {success, kick_index} where kick_index is the index of the kick that
## succeeded (0 = no kick; 1..4 = wall kicks) or -1 on failure.
func rotate(dir: int) -> Dictionary:
	if _game_over or piece == null or (dir != 1 and dir != -1):
		return {"success": false, "kick_index": -1}
	var from_rot: int = piece.rot
	var to_rot: int = PieceKind.rotate_cw(from_rot) if dir == 1 else PieceKind.rotate_ccw(from_rot)
	var offsets = Kicks.offsets(piece.kind, from_rot, to_rot)
	for i in range(offsets.size()):
		var off: Vector2i = offsets[i]
		var candidate: Vector2i = piece.origin + off
		if board.can_place(piece, candidate, to_rot):
			piece.origin = candidate
			piece.rot = to_rot
			_last_kick_index = i
			_on_successful_move()
			return {"success": true, "kick_index": i}
	return {"success": false, "kick_index": -1}

func soft_drop() -> int:
	if _game_over or piece == null:
		return 0
	if not board.can_place(piece, piece.origin + Vector2i(0, 1), piece.rot):
		return 0
	piece.origin += Vector2i(0, 1)
	scoring.add_soft_drop(1)
	# A successful soft-drop step counts as a downward step → resets the
	# lock-delay reset counter back to 0 (Guideline-compliant).
	_lock_resets = 0
	_recompute_grounded()
	return 1

## Rate-limited held-down soft drop. Caller passes elapsed real ms; we accumulate
## and call `soft_drop()` at most once per Guideline interval (20× gravity).
## Returns the number of cells dropped this call (0..n). Decoupling from frame
## rate keeps soft-drop deterministic across 60 / 144 Hz / headless tests.
func soft_drop_tick(dt_ms: int) -> int:
	if _game_over or piece == null or dt_ms <= 0:
		return 0
	var step_ms: int = max(1, Levels.ms_per_row(scoring.level) / 20)
	_soft_drop_ms_owed += dt_ms
	var dropped: int = 0
	while _soft_drop_ms_owed >= step_ms:
		_soft_drop_ms_owed -= step_ms
		if soft_drop() == 0:
			_soft_drop_ms_owed = 0
			break
		dropped += 1
	return dropped

func soft_drop_release() -> void:
	_soft_drop_ms_owed = 0

func hard_drop() -> int:
	if _game_over or piece == null:
		return 0
	var rows: int = 0
	while board.can_place(piece, piece.origin + Vector2i(0, 1), piece.rot):
		piece.origin += Vector2i(0, 1)
		rows += 1
	scoring.add_hard_drop(rows)
	_lock_piece(true)
	return rows

func hold() -> bool:
	if _game_over or piece == null or hold_used:
		return false
	var current_kind: int = piece.kind
	if held_kind == -1:
		# First hold: pull next from bag.
		held_kind = current_kind
		_spawn_specific(bag.next())
	else:
		var swap_kind: int = held_kind
		held_kind = current_kind
		_spawn_specific(swap_kind)
	hold_used = true
	return true

func can_hold() -> bool:
	return not hold_used and not _game_over

func held_piece() -> int:
	return held_kind

func current_piece() -> Piece:
	return piece

func is_game_over() -> bool:
	return _game_over

func score() -> int:
	return scoring.score

func level() -> int:
	return scoring.level

func lines_cleared() -> int:
	return scoring.lines

func next_queue(n: int = 5) -> Array:
	return bag.peek(n)

func ghost_position() -> Vector2i:
	if piece == null:
		return Vector2i.ZERO
	var origin: Vector2i = piece.origin
	while board.can_place(piece, origin + Vector2i(0, 1), piece.rot):
		origin += Vector2i(0, 1)
	return origin

func snapshot() -> Dictionary:
	return {
		"cells": board.snapshot(),
		"piece_kind": piece.kind if piece else 0,
		"piece_origin": piece.origin if piece else Vector2i.ZERO,
		"piece_rot": piece.rot if piece else 0,
		"held": held_kind,
		"hold_used": hold_used,
		"score": scoring.score,
		"level": scoring.level,
		"lines": scoring.lines,
		"combo": scoring.combo,
		"b2b": scoring.b2b,
		"game_over": _game_over,
	}

# --- Internals ---

func _advance_gravity(dt_ms: int) -> void:
	if dt_ms <= 0:
		return
	var step_ms: int = Levels.ms_per_row(scoring.level)
	_gravity_ms_owed += dt_ms
	while _gravity_ms_owed >= step_ms:
		_gravity_ms_owed -= step_ms
		if board.can_place(piece, piece.origin + Vector2i(0, 1), piece.rot):
			piece.origin += Vector2i(0, 1)
			# Falling resets lock-delay reset counter.
			_lock_resets = 0
			_lock_ms_owed = 0
			_recompute_grounded()
		else:
			_recompute_grounded()
			break

func _advance_lock_delay(dt_ms: int) -> void:
	if not _is_grounded:
		_lock_ms_owed = 0
		return
	_lock_ms_owed += dt_ms
	if _lock_ms_owed >= LOCK_DELAY_MS:
		_lock_piece(false)

func _recompute_grounded() -> void:
	_is_grounded = not board.can_place(piece, piece.origin + Vector2i(0, 1), piece.rot)
	if not _is_grounded:
		_lock_ms_owed = 0

# Called after a successful move/rotate. Resets the lock timer if grounded,
# capped at LOCK_RESET_CAP per piece (downward steps reset the cap).
func _on_successful_move() -> void:
	_recompute_grounded()
	if _is_grounded and _lock_resets < LOCK_RESET_CAP:
		_lock_ms_owed = 0
		_lock_resets += 1

func _spawn_next() -> void:
	_spawn_specific(bag.next())

func _spawn_specific(kind: int) -> void:
	piece = Piece.spawn(kind)
	hold_used = false
	_lock_resets = 0
	_lock_ms_owed = 0
	_gravity_ms_owed = 0
	_soft_drop_ms_owed = 0
	_is_grounded = false
	_last_kick_index = -1
	# Block-out: if the spawn position is already blocked, the game ends with
	# BLOCK_OUT before the player can do anything.
	if not board.can_place(piece, piece.origin, piece.rot):
		_end_game(REASON_BLOCK_OUT)
		piece = null
		return
	_recompute_grounded()

# `from_hard_drop`: hard drops bypass the lock delay timer entirely.
func _lock_piece(from_hard_drop: bool) -> void:
	if piece == null:
		return
	# T-spin classification before locking and clearing lines.
	var t_spin: int = TSpin.NONE
	# Only T pieces with a recent successful rotation are eligible. Hard drop
	# also disqualifies — drops can't be T-spins.
	if piece.kind == PieceKind.Kind.T and not from_hard_drop and _last_kick_index >= 0:
		t_spin = TSpin.classify(piece, _last_kick_index, board)

	board.lock_piece(piece)

	# Lock-out check: if every cell of the locked piece is above the visible
	# field (row < VISIBLE_TOP), end the game with LOCK_OUT.
	var all_above_visible: bool = true
	for c in piece.cells():
		if c.y >= Board.VISIBLE_TOP:
			all_above_visible = false
			break
	if all_above_visible:
		var locked_kind: int = piece.kind
		piece = null
		_emit_lock(t_spin, 0, locked_kind, false)
		_end_game(REASON_LOCK_OUT)
		return

	var cleared_rows: Array = board.full_rows()
	var rows_cleared: int = board.clear_rows(cleared_rows)
	# Perfect clear detection: board fully empty after the clear.
	var perfect: bool = _board_is_empty()

	var b2b_before: int = scoring.b2b
	scoring.register_lock(rows_cleared, t_spin)
	if perfect and rows_cleared > 0:
		scoring.register_perfect_clear(rows_cleared, b2b_before >= 0)

	var locked_kind: int = piece.kind
	piece = null
	_emit_lock(t_spin, rows_cleared, locked_kind, perfect, cleared_rows)

	# Spawn next piece (may end the game with BLOCK_OUT).
	_spawn_next()

func _emit_lock(t_spin: int, rows: int, kind: int, perfect: bool, cleared_rows: Array = []) -> void:
	emit_signal("piece_locked", {
		"kind": kind,
		"rows": rows,
		"cleared_rows": cleared_rows,
		"t_spin": t_spin,
		"b2b": scoring.b2b >= 0,
		"combo": max(0, scoring.combo),
		"perfect_clear": perfect,
	})

func _end_game(reason: int) -> void:
	if _game_over:
		return
	_game_over = true
	emit_signal("game_over", reason)

func _board_is_empty() -> bool:
	for v in board.cells:
		if v != 0:
			return false
	return true
