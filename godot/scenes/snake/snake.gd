extends Control
## Snake top-level scene. Wires InputManager → SnakeGameState → board view.
##
## Implements the GameHost duck-typed contract (start/pause/resume/teardown +
## exit_requested / score_reported signals). Mirrors scenes/tetris/tetris.gd
## structure so future games converge on a single template.
##
## start(seed) honours an explicit caller seed; menu (#6) always passes one.
## A seed of 0 is allowed (deterministic), per PRD #18: no Time-based default.

const SnakeConfig := preload("res://scripts/snake/core/snake_config.gd")
const SnakeGameState := preload("res://scripts/snake/core/snake_state.gd")
const Board := preload("res://scenes/snake/view/board.gd")
const HUD := preload("res://scenes/snake/view/hud.gd")
const PauseOverlay := preload("res://scenes/snake/view/pause_overlay.gd")
const GameOverOverlay := preload("res://scenes/snake/view/game_over_overlay.gd")

# GameHost contract.
signal exit_requested()
signal score_reported(value: int)

# Touch swipe threshold (px). Smaller swipes are ignored.
const SWIPE_MIN_PX: float = 24.0

enum Phase { PLAYING, PAUSED, GAME_OVER }

@onready var board: Node2D = $HBox/BoardHost/Board
@onready var hud: VBoxContainer = $HBox/Side/HUD
@onready var pause_overlay: CanvasLayer = $PauseOverlay
@onready var game_over_overlay: CanvasLayer = $GameOverOverlay

var state: SnakeGameState
var config: SnakeConfig
var _phase: int = Phase.PLAYING
var _logical_now_ms: int = 0
var _last_real_ms: int = 0
var _started: bool = false
var _last_reported_score: int = -1
var _seed: int = 0

# Touch swipe tracking. -1 = no active touch.
var _touch_index: int = -1
var _touch_start: Vector2 = Vector2.ZERO

func _ready() -> void:
	pause_overlay.visible = false
	game_over_overlay.visible = false
	InputManager.action_pressed.connect(_on_action_pressed)
	InputManager.action_repeated.connect(_on_action_repeated)
	game_over_overlay.restart_requested.connect(_on_restart_pressed)
	game_over_overlay.menu_requested.connect(_on_menu_pressed)
	pause_overlay.menu_requested.connect(_on_menu_pressed)
	# Standalone launch (project main_scene == us; or scene loaded directly in
	# a test). Auto-start with a deterministic seed (0). Tests override state.
	if get_tree().current_scene == self:
		start(0)

# --- GameHost contract ---

func start(seed_value: int = 0) -> void:
	_seed = seed_value
	config = SnakeConfig.new()
	state = SnakeGameState.create(_seed, config)
	board.configure(config.grid_w, config.grid_h, config.walls)
	_phase = Phase.PLAYING
	_logical_now_ms = 0
	_last_real_ms = _real_now()
	_last_reported_score = -1
	pause_overlay.visible = false
	game_over_overlay.visible = false
	_started = true
	_update_views()

func pause() -> void:
	if _phase == Phase.PLAYING:
		_phase = Phase.PAUSED
		pause_overlay.visible = true

func resume() -> void:
	if _phase == Phase.PAUSED:
		_phase = Phase.PLAYING
		pause_overlay.visible = false
		_last_real_ms = _real_now()
		# Shift core's internal clock so the resumed step doesn't try to catch
		# up the paused wall-clock interval.
		if state != null:
			state.set_last_tick(_logical_now_ms)

func teardown() -> void:
	if InputManager.action_pressed.is_connected(_on_action_pressed):
		InputManager.action_pressed.disconnect(_on_action_pressed)
	if InputManager.action_repeated.is_connected(_on_action_repeated):
		InputManager.action_repeated.disconnect(_on_action_repeated)
	state = null
	config = null
	_started = false

# --- Loop ---

func _process(_delta: float) -> void:
	if not _started:
		return
	var real_now: int = _real_now()
	var dt: int = max(0, real_now - _last_real_ms)
	_last_real_ms = real_now
	match _phase:
		Phase.PLAYING:
			_logical_now_ms += dt
			if state.tick(_logical_now_ms):
				_update_views()
			if state.is_game_over():
				_enter_game_over()
		Phase.PAUSED:
			pass
		Phase.GAME_OVER:
			pass

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		# Don't credit time spent unfocused as logical time.
		_last_real_ms = _real_now()
		if state != null:
			state.set_last_tick(_logical_now_ms)

# --- View ---

func _update_views() -> void:
	if state == null:
		return
	var snap: Dictionary = state.snapshot()
	board.update_from_snapshot(snap)
	hud.update_from_snapshot(snap)
	var s: int = int(snap.get("score", 0))
	if s != _last_reported_score:
		_last_reported_score = s
		score_reported.emit(s)

# --- Input: action signals ---

func _on_action_pressed(action: StringName) -> void:
	_handle_action(action, false)

func _on_action_repeated(action: StringName) -> void:
	_handle_action(action, true)

func _handle_action(action: StringName, _is_repeat: bool) -> void:
	if action == &"pause":
		_toggle_pause()
		return
	if _phase != Phase.PLAYING:
		return
	if state == null:
		return
	match action:
		&"move_up":
			state.turn(SnakeGameState.Dir.UP)
		&"move_down":
			state.turn(SnakeGameState.Dir.DOWN)
		&"move_left":
			state.turn(SnakeGameState.Dir.LEFT)
		&"move_right":
			state.turn(SnakeGameState.Dir.RIGHT)

# --- Input: touch swipe ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			# Track the first finger only; ignore additional fingers.
			if _touch_index == -1:
				_touch_index = t.index
				_touch_start = t.position
		else:
			if t.index == _touch_index:
				_resolve_swipe(t.position - _touch_start)
				_touch_index = -1

func _resolve_swipe(delta: Vector2) -> void:
	if _phase != Phase.PLAYING or state == null:
		return
	var ax: float = absf(delta.x)
	var ay: float = absf(delta.y)
	if maxf(ax, ay) < SWIPE_MIN_PX:
		return
	if ax >= ay:
		state.turn(SnakeGameState.Dir.RIGHT if delta.x > 0 else SnakeGameState.Dir.LEFT)
	else:
		state.turn(SnakeGameState.Dir.DOWN if delta.y > 0 else SnakeGameState.Dir.UP)

# --- Pause / game over / restart ---

func _toggle_pause() -> void:
	if _phase == Phase.PLAYING:
		pause()
	elif _phase == Phase.PAUSED:
		resume()

func _enter_game_over() -> void:
	if _phase == Phase.GAME_OVER:
		return
	_phase = Phase.GAME_OVER
	var snap: Dictionary = state.snapshot()
	game_over_overlay.show_with(int(snap.get("score", 0)), int(snap.get("level", 1)))

func _on_restart_pressed() -> void:
	game_over_overlay.visible = false
	# Fresh seed for replay; tests override start() afterwards if needed.
	start(_seed + 1)

func _on_menu_pressed() -> void:
	exit_requested.emit()

func _real_now() -> int:
	return Time.get_ticks_msec()
