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

# Audio mapping. Paths point at gitignored Tetris assets; missing files are
# tolerated by SfxLibrary/BgmPlayer (see issue #43, godot/assets/audio/README).
const TETRIS_SFX := {
	&"move":          "res://assets/audio/tetris/move.mp3",
	&"rotate":        "res://assets/audio/tetris/rotate.mp3",
	&"hard_drop":     "res://assets/audio/tetris/hardDrop.mp3",
	&"lock":          "res://assets/audio/tetris/lock.mp3",
	&"line_clear":    "res://assets/audio/tetris/lineClear.mp3",
	&"tetris":        "res://assets/audio/tetris/tetris.mp3",
	&"b2b_tetris":    "res://assets/audio/tetris/backToBackTetris.mp3",
	&"collapse":      "res://assets/audio/tetris/collapse.mp3",
	&"level_up":      "res://assets/audio/tetris/levelUp.mp3",
	&"hold":          "res://assets/audio/tetris/hold.mp3",
	&"input_failed":  "res://assets/audio/tetris/inputFailed.mp3",
	&"game_over":     "res://assets/audio/tetris/blockout.mp3",
	&"perfect_clear": "res://assets/audio/tetris/win.mp3",
}
const TETRIS_BGM_THEME := "res://assets/audio/tetris/Korobeiniki-FVR-01.mp3"

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

# Audio. _sfx / _bgm read from autoloads in _ready(); tests replace them via
# _inject_audio() before start(). Object typing keeps the test recorder
# duck-typed instead of forcing it to extend SfxLibrary.
var _sfx: Object
var _bgm: Object
# Set true on a hard-drop press BEFORE state.hard_drop() runs (which emits
# piece_locked synchronously). _on_piece_locked checks the flag so it doesn't
# add a redundant `lock` SFX on top of the `hard_drop` SFX.
var _hard_drop_this_frame: bool = false
# Emit a level-up cue when state.level() steps. Initialized at _init_state.
var _last_level: int = 1
# BGM is started once per scene-life (not per restart).
var _bgm_started: bool = false

func _ready() -> void:
	pause_overlay.visible = false
	game_over_overlay.visible = false
	# Resolve audio singletons into instance fields so tests can swap them via
	# _inject_audio() before start(). get_node tolerates missing autoloads in
	# weird test setups by returning null; we fall back to a silent stub.
	_sfx = get_node_or_null("/root/SfxLibrary")
	_bgm = get_node_or_null("/root/BgmPlayer")
	if _sfx == null:
		_sfx = _NullAudio.new()
		add_child(_sfx)
	if _bgm == null:
		_bgm = _NullAudio.new()
		add_child(_bgm)
	# Idempotent registration — safe to call on every scene re-enter.
	if _sfx.has_method("register_many"):
		_sfx.register_many(&"tetris", TETRIS_SFX)
	if _bgm.has_method("register_track"):
		_bgm.register_track(&"tetris", &"theme", TETRIS_BGM_THEME)
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
	# Start theme on the first start() call only — restarts (Game Over → R)
	# leave music playing rather than restarting from track-0.
	if not _bgm_started:
		if _bgm.has_method("play_track"):
			_bgm.play_track(&"tetris", &"theme")
		_bgm_started = true

func pause() -> void:
	if _phase == Phase.PLAYING:
		_phase = Phase.PAUSED
		pause_overlay.visible = true
		if _bgm.has_method("pause"):
			_bgm.pause()
		AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), true)

func resume() -> void:
	if _phase == Phase.PAUSED:
		_phase = Phase.PLAYING
		pause_overlay.visible = false
		# Don't credit paused wall-clock time as logical time on resume.
		_last_real_ms = _real_now()
		if _bgm.has_method("resume"):
			_bgm.resume()
		AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), false)

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
			# Level-up cue: state.level() steps when enough lines are cleared.
			var lvl: int = state.level()
			if lvl != _last_level:
				_last_level = lvl
				_play_sfx(&"level_up")
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
				_play_sfx(&"collapse")
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
	_last_level = state.level()
	_hard_drop_this_frame = false
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
			var r := state.move(-1)
			if r.success:
				_play_sfx(&"move")
			elif not is_repeat:
				_play_sfx(&"input_failed")
		&"move_right":
			var r := state.move(1)
			if r.success:
				_play_sfx(&"move")
			elif not is_repeat:
				_play_sfx(&"input_failed")
		&"rotate_cw":
			if not is_repeat:
				var r := state.rotate(1)
				if r.success:
					_play_sfx(&"rotate")
				else:
					_play_sfx(&"input_failed")
		&"rotate_ccw":
			if not is_repeat:
				var r := state.rotate(-1)
				if r.success:
					_play_sfx(&"rotate")
				else:
					_play_sfx(&"input_failed")
		&"hard_drop":
			if not is_repeat:
				# MUST set the flag BEFORE state.hard_drop(): hard_drop emits
				# piece_locked synchronously and _on_piece_locked checks the
				# flag to suppress its own `lock` SFX in favor of `hard_drop`.
				_hard_drop_this_frame = true
				_play_sfx(&"hard_drop")
				state.hard_drop()
		&"hold":
			if not is_repeat:
				if state.hold():
					_play_sfx(&"hold")
				else:
					_play_sfx(&"input_failed")

# --- State signals ---

func _on_piece_locked(result: Dictionary) -> void:
	var rows: int = result.get("rows", 0)
	# Lock SFX is suppressed when a hard-drop produced this lock (the hard_drop
	# SFX has already played in _handle_action). For soft-drop / natural locks
	# without a clear, play the dry "lock" thunk.
	if _hard_drop_this_frame:
		_hard_drop_this_frame = false
	elif rows == 0:
		_play_sfx(&"lock")
	# Line-clear cues. b2b distinguishes consecutive 4-line clears.
	if rows >= 1 and rows <= 3:
		_play_sfx(&"line_clear")
	elif rows == 4:
		var b2b: bool = bool(result.get("b2b", false))
		_play_sfx(&"b2b_tetris" if b2b else &"tetris")
	# All-clear stinger on top of the line-clear cue.
	if bool(result.get("perfect_clear", false)):
		_play_sfx(&"perfect_clear")
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
	_play_sfx(&"game_over")
	if _bgm.has_method("stop_track"):
		_bgm.stop_track()
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
	# game_over stopped the BGM; resume it for the new run.
	if _bgm.has_method("play_track"):
		_bgm.play_track(&"tetris", &"theme")

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

# --- Audio helpers ---

## Wrapper that respects a possibly-null / duck-typed _sfx field. Tests inject
## a recorder via _inject_audio() that exposes `play(ns, event)` (and nothing
## else); this helper insulates the wiring code from that contract.
func _play_sfx(event: StringName) -> void:
	if _sfx != null and _sfx.has_method("play"):
		_sfx.play(&"tetris", event)

## Test seam: replace the autoload references before start(seed). Normally
## set in _ready() to /root/SfxLibrary and /root/BgmPlayer. Tests pass a
## recorder Object that exposes `play(ns, event)` (sfx) and any of
## `play_track`/`stop_track`/`pause`/`resume`/`register_track` (bgm).
func _inject_audio(sfx: Object, bgm: Object) -> void:
	_sfx = sfx
	_bgm = bgm

## Silent stub used when /root/SfxLibrary or /root/BgmPlayer aren't present
## (e.g. unit tests that load tetris.tscn directly without the autoloads).
class _NullAudio extends Node:
	func register_many(_ns: StringName, _mapping: Dictionary) -> void:
		pass
	func register_track(_ns: StringName, _name: StringName, _path: String) -> bool:
		return false
	func play(_ns: StringName, _event: StringName, _volume_db: float = 0.0) -> void:
		pass
	func play_track(_ns: StringName, _name: StringName, _fade_in: float = 0.5) -> void:
		pass
	func stop_track(_fade_out: float = 0.5) -> void:
		pass
	func pause() -> void:
		pass
	func resume() -> void:
		pass
