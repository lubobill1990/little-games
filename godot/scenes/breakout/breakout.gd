extends Control
## Breakout top-level scene. Wires InputManager → BreakoutGameState → world view.
##
## Implements the GameHost duck-typed contract (start/pause/resume/teardown +
## exit_requested / score_reported signals). Mirrors scenes/snake/snake.gd
## and scenes/g2048/g2048.gd structure.
##
## Render model: world.gd draws in world-units (config.world_w × world_h);
## this scene applies a uniform fit-letterbox transform to the BoardHost
## Control on every viewport resize.

const BreakoutConfig := preload("res://scripts/breakout/core/breakout_config.gd")
const BreakoutLevel := preload("res://scripts/breakout/core/breakout_level.gd")
const BreakoutGameState := preload("res://scripts/breakout/core/breakout_state.gd")
const World := preload("res://scenes/breakout/view/world.gd")
const HUD := preload("res://scenes/breakout/view/hud.gd")
const PauseOverlay := preload("res://scenes/breakout/view/pause_overlay.gd")
const LifeLostOverlay := preload("res://scenes/breakout/view/life_lost_overlay.gd")
const GameOverOverlay := preload("res://scenes/breakout/view/game_over_overlay.gd")
const WinOverlay := preload("res://scenes/breakout/view/win_overlay.gd")

const DEFAULT_LEVEL_PATH: String = "res://scenes/breakout/levels/level_01.tres"

# GameHost contract.
signal exit_requested()
signal score_reported(value: int)

const SWIPE_MIN_PX_LAUNCH_ZONE: float = 24.0
const LIFE_LOST_OVERLAY_MS: int = 800

enum Phase { PLAYING, PAUSED, LIFE_LOST, GAME_OVER, WON }

@onready var board_host: Control = $HBox/BoardHost
@onready var world: Node2D = $HBox/BoardHost/World
@onready var hud: VBoxContainer = $HBox/Side/HUD
@onready var pause_overlay: CanvasLayer = $PauseOverlay
@onready var life_lost_overlay: CanvasLayer = $LifeLostOverlay
@onready var game_over_overlay: CanvasLayer = $GameOverOverlay
@onready var win_overlay: CanvasLayer = $WinOverlay

var state: BreakoutGameState
var config: BreakoutConfig
var level: BreakoutLevel
var _phase: int = Phase.PLAYING
var _logical_now_ms: int = 0
var _last_real_ms: int = 0
var _started: bool = false
var _last_reported_score: int = -1
var _seed: int = 0
var _level_index: int = 1
var _life_lost_until_ms: int = -1
var _last_lives: int = -1

# Touch tracking. Drag = paddle target; quick tap on lower 25% = launch.
var _touch_index: int = -1
var _touch_start: Vector2 = Vector2.ZERO
var _touch_world_target_x: float = -1.0   # world-coord paddle target; -1 = none

# Cached letterbox transform.
var _world_to_local_scale: float = 1.0
var _world_to_local_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	pause_overlay.visible = false
	life_lost_overlay.visible = false
	game_over_overlay.visible = false
	win_overlay.visible = false
	InputManager.action_pressed.connect(_on_action_pressed)
	game_over_overlay.restart_requested.connect(_on_restart_pressed)
	game_over_overlay.menu_requested.connect(_on_menu_pressed)
	pause_overlay.menu_requested.connect(_on_menu_pressed)
	win_overlay.restart_requested.connect(_on_restart_pressed)
	win_overlay.menu_requested.connect(_on_menu_pressed)
	board_host.resized.connect(_recompute_letterbox)
	# Standalone launch: auto-start with deterministic seed 0.
	if get_tree().current_scene == self:
		start(0)

# --- GameHost contract ---

func start(seed_value: int = 0) -> void:
	_seed = seed_value
	config = BreakoutConfig.new()
	level = load(DEFAULT_LEVEL_PATH) as BreakoutLevel
	if level == null:
		push_error("Breakout: failed to load %s" % DEFAULT_LEVEL_PATH)
		return
	state = BreakoutGameState.create(_seed, config, level)
	world.configure(config.world_w, config.world_h, config.ball_radius, _build_brick_meta())
	_phase = Phase.PLAYING
	_logical_now_ms = 0
	_last_real_ms = _real_now()
	_last_reported_score = -1
	_last_lives = -1
	_life_lost_until_ms = -1
	_touch_index = -1
	_touch_world_target_x = -1.0
	pause_overlay.visible = false
	life_lost_overlay.visible = false
	game_over_overlay.visible = false
	win_overlay.visible = false
	_started = true
	_recompute_letterbox()
	_update_views()

func pause() -> void:
	if _phase == Phase.PLAYING or _phase == Phase.LIFE_LOST:
		_phase = Phase.PAUSED if _phase == Phase.PLAYING else Phase.PAUSED
		pause_overlay.visible = true

func resume() -> void:
	if _phase == Phase.PAUSED:
		_phase = Phase.PLAYING
		pause_overlay.visible = false
		_last_real_ms = _real_now()

func teardown() -> void:
	if InputManager.action_pressed.is_connected(_on_action_pressed):
		InputManager.action_pressed.disconnect(_on_action_pressed)
	state = null
	config = null
	level = null
	_started = false

# --- Loop ---

func _process(_delta: float) -> void:
	if not _started or state == null:
		return
	var real_now: int = _real_now()
	var dt: int = max(0, real_now - _last_real_ms)
	_last_real_ms = real_now
	if _phase == Phase.PAUSED or _phase == Phase.GAME_OVER or _phase == Phase.WON:
		return
	_logical_now_ms += dt
	# Compute paddle intent each frame from input. Touch target overrides
	# digital/analog if active.
	state.set_paddle_intent(_compute_paddle_intent_px_s(dt))
	var changed: bool = state.tick(_logical_now_ms)
	if changed:
		_update_views()
	# Mode transitions.
	if state.is_won() and _phase != Phase.WON:
		_enter_won()
		return
	if state.is_game_over() and _phase != Phase.GAME_OVER:
		_enter_game_over()
		return
	# Life-lost overlay timeout.
	if _phase == Phase.LIFE_LOST and _logical_now_ms >= _life_lost_until_ms:
		_phase = Phase.PLAYING
		life_lost_overlay.visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_last_real_ms = _real_now()

# --- Paddle intent ---

func _compute_paddle_intent_px_s(dt_ms: int) -> float:
	# Touch drag: lerp paddle x toward finger target with max speed.
	if _touch_world_target_x >= 0.0 and state != null:
		var dx: float = _touch_world_target_x - state.paddle_x
		if absf(dx) < 0.5:
			return 0.0
		# Convert "want to move dx px in dt_ms ms" to px/s, clamped at apply.
		var seconds: float = maxf(float(dt_ms) / 1000.0, 0.001)
		return clampf(dx / seconds, -config.paddle_max_speed_px_s, config.paddle_max_speed_px_s)
	# Digital + analog: action-strength delta.
	var right: float = Input.get_action_strength(&"move_right")
	var left: float = Input.get_action_strength(&"move_left")
	var axis: float = clampf(right - left, -1.0, 1.0)
	return axis * config.paddle_max_speed_px_s

# --- View ---

func _update_views() -> void:
	if state == null:
		return
	var snap: Dictionary = state.snapshot()
	world.update_from_snapshot(snap)
	hud.update_from_snapshot(snap, _level_index)
	# Detect life loss → trigger life-lost overlay.
	var lives: int = int(snap.get("lives", 0))
	if _last_lives >= 0 and lives < _last_lives and lives > 0 and int(snap.get("mode", -1)) == BreakoutGameState.Mode.STICKY:
		_phase = Phase.LIFE_LOST
		life_lost_overlay.set_lives(lives)
		life_lost_overlay.visible = true
		_life_lost_until_ms = _logical_now_ms + LIFE_LOST_OVERLAY_MS
	_last_lives = lives
	var s: int = int(snap.get("score", 0))
	if s != _last_reported_score:
		_last_reported_score = s
		score_reported.emit(s)

func _build_brick_meta() -> Dictionary:
	# Mirror BreakoutGameState._expand_level_to_bricks logic so the renderer
	# can resolve idx → {cx, cy, hx, hy, color_id, destructible}. Snapshot
	# only carries idx + hp; this static metadata stays constant per level.
	var out: Dictionary = {}
	if level == null:
		return out
	var hx: float = level.brick_w * 0.5
	var hy: float = level.brick_h * 0.5
	var n: int = level.cells.size()
	for i in n:
		var cell: Variant = level.cells[i]
		if not (cell is Dictionary):
			continue
		var d: Dictionary = cell
		var hp: int = int(d.get("hp", 0))
		if hp <= 0:
			continue
		var col: int = i % level.cols
		var row: int = i / level.cols
		var cx: float = level.origin_x + col * level.brick_w + hx
		var cy: float = level.origin_y + row * level.brick_h + hy
		out[i] = {
			"cx": cx, "cy": cy, "hx": hx, "hy": hy,
			"color_id": int(d.get("color_id", 0)),
			"destructible": bool(d.get("destructible", true)),
		}
	return out

# --- Letterbox ---

func _recompute_letterbox() -> void:
	if config == null:
		return
	var avail: Vector2 = board_host.size
	if avail.x <= 0.0 or avail.y <= 0.0:
		return
	var sx: float = avail.x / config.world_w
	var sy: float = avail.y / config.world_h
	var s: float = minf(sx, sy)
	var used: Vector2 = Vector2(config.world_w, config.world_h) * s
	var off: Vector2 = (avail - used) * 0.5
	_world_to_local_scale = s
	_world_to_local_offset = off
	if world != null:
		world.position = off
		world.scale = Vector2(s, s)

func _local_to_world(local: Vector2) -> Vector2:
	if _world_to_local_scale <= 0.0:
		return Vector2.ZERO
	return (local - _world_to_local_offset) / _world_to_local_scale

# --- Input: action signals ---

func _on_action_pressed(action: StringName) -> void:
	if action == &"pause":
		_toggle_pause()
		return
	if _phase != Phase.PLAYING and _phase != Phase.LIFE_LOST:
		return
	if state == null:
		return
	if action == &"hard_drop":
		state.launch()

# --- Input: touch ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)

func _handle_touch(t: InputEventScreenTouch) -> void:
	if _phase != Phase.PLAYING and _phase != Phase.LIFE_LOST:
		return
	if t.pressed:
		if _touch_index == -1:
			_touch_index = t.index
			_touch_start = t.position
			# Set initial paddle target from touch position.
			var w: Vector2 = _local_to_world(board_host.get_local_mouse_position())
			# board_host's local mouse position isn't reliable for synthetic events;
			# convert from touch global instead.
			w = _local_to_world(board_host.to_local(t.position))
			_touch_world_target_x = clampf(w.x, 0.0, config.world_w)
	else:
		if t.index == _touch_index:
			# Tap = small movement and on lower 25% triggers launch.
			var delta: Vector2 = t.position - _touch_start
			if delta.length() < SWIPE_MIN_PX_LAUNCH_ZONE:
				var w: Vector2 = _local_to_world(board_host.to_local(t.position))
				if w.y >= config.world_h * 0.75 and state != null:
					state.launch()
			_touch_index = -1
			_touch_world_target_x = -1.0

func _handle_drag(d: InputEventScreenDrag) -> void:
	if d.index != _touch_index:
		return
	if _phase != Phase.PLAYING and _phase != Phase.LIFE_LOST:
		return
	var w: Vector2 = _local_to_world(board_host.to_local(d.position))
	_touch_world_target_x = clampf(w.x, 0.0, config.world_w)

# --- Phase transitions ---

func _toggle_pause() -> void:
	if _phase == Phase.PLAYING or _phase == Phase.LIFE_LOST:
		pause()
	elif _phase == Phase.PAUSED:
		resume()

func _enter_game_over() -> void:
	_phase = Phase.GAME_OVER
	life_lost_overlay.visible = false
	var snap: Dictionary = state.snapshot()
	game_over_overlay.show_with(int(snap.get("score", 0)))

func _enter_won() -> void:
	_phase = Phase.WON
	life_lost_overlay.visible = false
	var snap: Dictionary = state.snapshot()
	win_overlay.show_with(int(snap.get("score", 0)))

func _on_restart_pressed() -> void:
	game_over_overlay.visible = false
	win_overlay.visible = false
	start(_seed + 1)

func _on_menu_pressed() -> void:
	exit_requested.emit()

func _real_now() -> int:
	return Time.get_ticks_msec()
