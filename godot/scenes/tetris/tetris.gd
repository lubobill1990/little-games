extends Control
## Tetris top-level scene. Wires InputManager → TetrisGameState → view.
##
## Implements the GameHost duck-typed contract (start/pause/resume/teardown +
## exit_requested signal) so the main menu can launch and reclaim it. When the
## scene is loaded directly as the project's main_scene, `_ready` calls
## `start(_fresh_seed())` itself so launching tetris.tscn standalone still
## works (e.g. integration tests that load the scene directly).

const TetrisGameState := preload("res://scripts/tetris/core/game_state.gd")
const Playfield := preload("res://scenes/tetris/view/playfield.gd")
const HUD := preload("res://scenes/tetris/view/hud.gd")
const NextQueue := preload("res://scenes/tetris/view/next_queue.gd")
const HoldSlot := preload("res://scenes/tetris/view/hold_slot.gd")
const PauseOverlay := preload("res://scenes/tetris/view/pause_overlay.gd")
const GameOverOverlay := preload("res://scenes/tetris/view/game_over_overlay.gd")

# Animation timing.
const FLASH_MS: int = 100
const SETTLE_MS: int = 150
const ANIM_TOTAL_MS: int = FLASH_MS + SETTLE_MS  # = 250 ms (Acceptance #5).

enum Phase { PLAYING, PAUSED, ANIMATING_FLASH, ANIMATING_SETTLE, GAME_OVER }

# GameHost contract.
signal exit_requested()
signal score_reported(value: int)

@onready var playfield: Node2D = $HBox/PlayfieldHost/Playfield
@onready var hud: VBoxContainer = $HBox/Side/HUD
@onready var next_queue: VBoxContainer = $HBox/Side/NextQueue
@onready var hold_slot: Control = $HBox/Side/HoldSlot
@onready var pause_overlay: CanvasLayer = $PauseOverlay
@onready var game_over_overlay: CanvasLayer = $GameOverOverlay

var state: TetrisGameState
var _phase: int = Phase.PLAYING
var _logical_now_ms: int = 0
var _last_real_ms: int = 0
var _anim_elapsed_ms: int = 0
var _flash_rows: Array = []
var _final_score: int = 0
var _final_lines: int = 0
var _final_level: int = 0
var _started: bool = false
var _last_reported_score: int = -1

# Buffered inputs during animation. Move accumulates as a delta (so multiple
# left-presses sum), rotate as a sign (last wins), hold as a flag.
var _buffered_move: int = 0
var _buffered_rotate: int = 0
var _buffered_hold: bool = false

func _ready() -> void:
	pause_overlay.visible = false
	game_over_overlay.visible = false
	# Subscribe to InputManager. action_pressed/action_repeated handle move repeats;
	# released doesn't affect tetris (soft-drop is polled per-frame).
	InputManager.action_pressed.connect(_on_action_pressed)
	InputManager.action_repeated.connect(_on_action_repeated)
	game_over_overlay.restart_requested.connect(_on_restart_pressed)
	game_over_overlay.menu_requested.connect(_on_menu_pressed)
	pause_overlay.menu_requested.connect(_on_menu_pressed)
	# Standalone launch: project main_scene == us. Auto-start so direct loads
	# (and the existing integration tests) keep working without a wrapper.
	if get_tree().current_scene == self:
		start(_fresh_seed())

# --- GameHost contract ---

func start(seed_value: int = 0) -> void:
	if seed_value == 0:
		seed_value = _fresh_seed()
	_init_state(seed_value)
	_last_real_ms = _real_now()
	_started = true

func pause() -> void:
	if _phase == Phase.PLAYING:
		_phase = Phase.PAUSED
		pause_overlay.visible = true

func resume() -> void:
	if _phase == Phase.PAUSED:
		_phase = Phase.PLAYING
		pause_overlay.visible = false
		# Don't credit paused wall-clock time as logical time on resume.
		_last_real_ms = _real_now()

func teardown() -> void:
	# Disconnect everything we connected so the host can free us cleanly.
	if InputManager.action_pressed.is_connected(_on_action_pressed):
		InputManager.action_pressed.disconnect(_on_action_pressed)
	if InputManager.action_repeated.is_connected(_on_action_repeated):
		InputManager.action_repeated.disconnect(_on_action_repeated)
	if state != null:
		if state.piece_locked.is_connected(_on_piece_locked):
			state.piece_locked.disconnect(_on_piece_locked)
		if state.game_over.is_connected(_on_game_over):
			state.game_over.disconnect(_on_game_over)
		state = null
	_started = false

func _process(delta: float) -> void:
	if not _started:
		return
	var real_now: int = _real_now()
	var dt: int = max(0, real_now - _last_real_ms)
	_last_real_ms = real_now

	match _phase:
		Phase.PLAYING:
			_logical_now_ms += dt
			# Rate-limited soft drop while the action is held; release zeroes the
			# accumulator so a tap on a fast level doesn't drop multiple cells.
			if InputManager.is_action_pressed(&"soft_drop"):
				state.soft_drop_tick(dt)
			else:
				state.soft_drop_release()
			state.tick(_logical_now_ms)
			_update_views()
			# Detect game-over (set asynchronously by spawn-block-out).
			if state.is_game_over():
				_enter_game_over()
		Phase.PAUSED:
			# Don't tick state; don't accumulate logical time.
			pass
		Phase.ANIMATING_FLASH:
			_anim_elapsed_ms += dt
			var flash_a: float = 1.0 - float(_anim_elapsed_ms) / float(FLASH_MS)
			playfield.set_flash(_flash_rows, flash_a)
			if _anim_elapsed_ms >= FLASH_MS:
				# Rows were already cleared by core in _lock_piece.
				playfield.set_flash([], 0.0)
				_phase = Phase.ANIMATING_SETTLE
				_anim_elapsed_ms = 0
				_update_views()
		Phase.ANIMATING_SETTLE:
			_anim_elapsed_ms += dt
			if _anim_elapsed_ms >= SETTLE_MS:
				_resume_after_animation()
		Phase.GAME_OVER:
			pass

# --- Setup ---

func _fresh_seed() -> int:
	return Time.get_ticks_msec() ^ (randi() & 0xFFFFFFFF)

func _init_state(seed_value: int) -> void:
	state = TetrisGameState.create(seed_value)
	state.piece_locked.connect(_on_piece_locked)
	state.game_over.connect(_on_game_over)
	playfield.bind(state)
	_logical_now_ms = 0
	_anim_elapsed_ms = 0
	_flash_rows = []
	_buffered_move = 0
	_buffered_rotate = 0
	_buffered_hold = false
	_phase = Phase.PLAYING
	_last_reported_score = -1
	_update_views()

func _real_now() -> int:
	return Time.get_ticks_msec()

# --- View updates ---

func _update_views() -> void:
	playfield.queue_redraw()
	hud.update_from(state)
	next_queue.update_from(state)
	hold_slot.update_from(state)
	var s: int = state.score()
	if s != _last_reported_score:
		_last_reported_score = s
		score_reported.emit(s)

# --- Input ---

func _on_action_pressed(action: StringName) -> void:
	_handle_action(action, false)

func _on_action_repeated(action: StringName) -> void:
	_handle_action(action, true)

func _handle_action(action: StringName, is_repeat: bool) -> void:
	# ui_accept only matters in game over (handled by overlay's own listener).
	if _phase == Phase.GAME_OVER:
		return
	if action == &"pause":
		if is_repeat:
			return
		_toggle_pause()
		return
	if _phase == Phase.PAUSED:
		return
	if _phase == Phase.ANIMATING_FLASH or _phase == Phase.ANIMATING_SETTLE:
		# Buffered subset of inputs (sub-agent review §reword).
		match action:
			&"move_left":
				_buffered_move -= 1
			&"move_right":
				_buffered_move += 1
			&"rotate_cw":
				_buffered_rotate = 1
			&"rotate_ccw":
				_buffered_rotate = -1
			&"hold":
				if not is_repeat:
					_buffered_hold = true
		return
	# PLAYING phase.
	match action:
		&"move_left":
			state.move(-1)
		&"move_right":
			state.move(1)
		&"rotate_cw":
			if not is_repeat:
				state.rotate(1)
		&"rotate_ccw":
			if not is_repeat:
				state.rotate(-1)
		&"hard_drop":
			if not is_repeat:
				state.hard_drop()
		&"hold":
			if not is_repeat:
				state.hold()

# --- State signals ---

func _on_piece_locked(result: Dictionary) -> void:
	var rows: int = result.get("rows", 0)
	if rows <= 0:
		return
	# Core has already cleared the rows by the time this signal fires; the
	# `cleared_rows` payload is the indices of rows that were full just before
	# clear, so we can overlay a flash band on those visible rows during the
	# animation phase. v1 caveat: rows are already gone underneath, so the
	# flash is a cosmetic-only band, not piece-colored. Acceptance #5 only
	# requires "flash → clear → settle within 250ms" + input gating, which
	# this satisfies.
	_flash_rows = result.get("cleared_rows", []).duplicate()
	_phase = Phase.ANIMATING_FLASH
	_anim_elapsed_ms = 0
	playfield.set_flash(_flash_rows, 1.0)
	_buffered_move = 0
	_buffered_rotate = 0
	_buffered_hold = false

func _on_game_over(_reason: int) -> void:
	_enter_game_over()

func _enter_game_over() -> void:
	if _phase == Phase.GAME_OVER:
		return
	_final_score = state.score()
	_final_lines = state.lines_cleared()
	_final_level = state.level()
	_phase = Phase.GAME_OVER
	game_over_overlay.show_with(_final_score, _final_lines, _final_level)
	_update_views()

func _on_restart_pressed() -> void:
	game_over_overlay.visible = false
	# Disconnect old state's signals.
	if state.piece_locked.is_connected(_on_piece_locked):
		state.piece_locked.disconnect(_on_piece_locked)
	if state.game_over.is_connected(_on_game_over):
		state.game_over.disconnect(_on_game_over)
	_init_state(_fresh_seed())

# --- Pause / animation ---

func _toggle_pause() -> void:
	if _phase == Phase.PLAYING:
		pause()
	elif _phase == Phase.PAUSED:
		resume()

func _on_menu_pressed() -> void:
	exit_requested.emit()

func _resume_after_animation() -> void:
	_phase = Phase.PLAYING
	playfield.set_flash([], 0.0)
	# Apply buffered inputs in order: move → rotate → hold.
	if _buffered_move != 0:
		var step: int = sign(_buffered_move)
		var remaining: int = abs(_buffered_move)
		while remaining > 0:
			if not state.move(step).success:
				break
			remaining -= 1
	if _buffered_rotate != 0:
		state.rotate(_buffered_rotate)
	if _buffered_hold:
		state.hold()
	_buffered_move = 0
	_buffered_rotate = 0
	_buffered_hold = false
	_update_views()
