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
const LevelPack := preload("res://scripts/breakout/level_pack.gd")
const SfxTones := preload("res://scripts/core/audio/sfx_tones.gd")
const SfxVolume := preload("res://scripts/core/audio/sfx_volume.gd")
const Haptics := preload("res://scripts/core/input/haptics.gd")

const DEFAULT_LEVEL_PATH: String = "res://scenes/breakout/levels/level_01.tres"
const BEST_RUN_KEY: StringName = &"breakout.best.run"

# Haptic tier table per Dev plan: (value_threshold, intensity, duration_ms).
# First row whose brick.value < threshold wins; last row is the cap.
const _BRICK_HAPTIC_TIERS: Array = [
	[50,    0.2,  60],
	[200,   0.4, 100],
	[INF,   0.7, 160],
]
const _LIFE_LOST_HAPTIC: Array = [0.6, 250]   # [intensity, duration_ms]
const _LEVEL_CLEAR_HAPTIC: Array = [0.8, 300]

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

# Polish state (issue #23): per-level best, run-score across pack, prior tick
# brick set + ball velocities for SFX/haptics dispatch.
var _level_score_offset: int = 0    # Run-score floor when starting current level.
var _last_brick_set: Dictionary = {}  # idx → hp at previous tick.
var _last_ball_vx: float = 0.0
var _last_ball_vy: float = 0.0
var _level_clear_sfx_played: bool = false
var _game_over_sfx_played: bool = false

# SFX players, created in _ready.
var _sfx_paddle: AudioStreamPlayer
var _sfx_brick: AudioStreamPlayer
var _sfx_wall: AudioStreamPlayer
var _sfx_life_lost: AudioStreamPlayer
var _sfx_level_clear: AudioStreamPlayer
var _sfx_game_over: AudioStreamPlayer

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
	_setup_sfx()
	InputManager.action_pressed.connect(_on_action_pressed)
	game_over_overlay.restart_requested.connect(_on_restart_pressed)
	game_over_overlay.menu_requested.connect(_on_menu_pressed)
	pause_overlay.menu_requested.connect(_on_menu_pressed)
	win_overlay.next_level_requested.connect(_on_next_level_pressed)
	win_overlay.restart_requested.connect(_on_restart_pressed)
	win_overlay.menu_requested.connect(_on_menu_pressed)
	board_host.resized.connect(_recompute_letterbox)
	if _has_settings():
		Settings.changed.connect(_on_settings_changed)
		_apply_sfx_volume()
	# Standalone launch: auto-start with deterministic seed 0.
	if get_tree().current_scene == self:
		start(0)


func _setup_sfx() -> void:
	_sfx_paddle = AudioStreamPlayer.new()
	_sfx_paddle.stream = SfxTones.tone(330.0, 0.05, 0.4)
	add_child(_sfx_paddle)
	_sfx_brick = AudioStreamPlayer.new()
	# Brick stream is replaced per-event with a value-tuned tone.
	add_child(_sfx_brick)
	_sfx_wall = AudioStreamPlayer.new()
	_sfx_wall.stream = SfxTones.tone(180.0, 0.04, 0.25)
	add_child(_sfx_wall)
	_sfx_life_lost = AudioStreamPlayer.new()
	_sfx_life_lost.stream = SfxTones.tone_sequence([
		Vector2(220.0, 0.10),
		Vector2(165.0, 0.18),
	])
	add_child(_sfx_life_lost)
	_sfx_level_clear = AudioStreamPlayer.new()
	_sfx_level_clear.stream = SfxTones.tone_sequence([
		Vector2(523.0, 0.08),
		Vector2(659.0, 0.08),
		Vector2(784.0, 0.08),
		Vector2(1047.0, 0.16),
	])
	add_child(_sfx_level_clear)
	_sfx_game_over = AudioStreamPlayer.new()
	_sfx_game_over.stream = SfxTones.tone_sequence([
		Vector2(330.0, 0.12),
		Vector2(247.0, 0.18),
		Vector2(165.0, 0.30),
	])
	add_child(_sfx_game_over)


func _has_settings() -> bool:
	return get_tree().root.has_node("Settings")


func _apply_sfx_volume() -> void:
	if not _has_settings():
		return
	var master: float = float(Settings.get_value(&"audio.master", 1.0))
	var sfx: float = float(Settings.get_value(&"audio.sfx", 1.0))
	var v: float = SfxVolume.linear_volume(master, sfx)
	for p in [_sfx_paddle, _sfx_brick, _sfx_wall, _sfx_life_lost, _sfx_level_clear, _sfx_game_over]:
		if p != null:
			SfxVolume.set_player_volume(p, v)


func _on_settings_changed(key: StringName) -> void:
	var s: String = String(key)
	if s == "audio.master" or s == "audio.sfx":
		_apply_sfx_volume()

# --- GameHost contract ---

func start(seed_value: int = 0) -> void:
	_seed = seed_value
	config = BreakoutConfig.new()
	# Fresh pack run: level 1, no carried score, fresh lives.
	_level_index = 1
	_level_score_offset = 0
	_load_level(_level_index, 0, config.lives_start)


## Configure state for `level_idx` (1-based), seeding score and lives carried
## over from the previous level. Used both by `start()` and by the win →
## next-level transition.
func _load_level(level_idx: int, carry_score: int, carry_lives: int) -> void:
	var path: String = LevelPack.path_for(level_idx)
	if path == "":
		push_error("Breakout: no level at index %d (pack size %d)" % [level_idx, LevelPack.size()])
		return
	level = load(path) as BreakoutLevel
	if level == null:
		push_error("Breakout: failed to load %s" % path)
		return
	state = BreakoutGameState.create(_seed + level_idx, config, level)
	# Carry score + lives across the transition (state.create resets them).
	state.score = carry_score
	state.lives = carry_lives
	world.configure(config.world_w, config.world_h, config.ball_radius, _build_brick_meta())
	_phase = Phase.PLAYING
	_logical_now_ms = 0
	_last_real_ms = _real_now()
	_last_reported_score = -1
	_last_lives = -1
	_life_lost_until_ms = -1
	_touch_index = -1
	_touch_world_target_x = -1.0
	_last_brick_set = _snapshot_brick_set(state.snapshot())
	_last_ball_vx = state.ball_vx
	_last_ball_vy = state.ball_vy
	_level_clear_sfx_played = false
	_game_over_sfx_played = false
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
	# Dispatch SFX / haptics before view updates so they're tied to the same
	# tick as the visible state change.
	_dispatch_sfx_and_haptics(snap)
	world.update_from_snapshot(snap)
	hud.update_from_snapshot(snap, _level_index)
	# Detect life loss → trigger life-lost overlay.
	var lives: int = int(snap.get("lives", 0))
	if _last_lives >= 0 and lives < _last_lives and lives > 0 and int(snap.get("mode", -1)) == BreakoutGameState.Mode.STICKY:
		_phase = Phase.LIFE_LOST
		life_lost_overlay.set_lives(lives)
		life_lost_overlay.visible = true
		_life_lost_until_ms = _logical_now_ms + LIFE_LOST_OVERLAY_MS
		# Life-lost SFX + longer haptic pulse.
		if _sfx_life_lost != null:
			_sfx_life_lost.play()
		Haptics.pulse(float(_LIFE_LOST_HAPTIC[0]), int(_LIFE_LOST_HAPTIC[1]))
	_last_lives = lives
	var s: int = int(snap.get("score", 0))
	if s != _last_reported_score:
		_last_reported_score = s
		score_reported.emit(s)


# Diff `snap.bricks` against `_last_brick_set` to detect destructions; play
# brick-break SFX / haptic per destruction. Also detect ball-velocity sign
# flips to play paddle / wall SFX (ball.vy flips up = paddle hit; ball.vx
# flips = side wall hit; ball.vy flips down on the top wall).
func _dispatch_sfx_and_haptics(snap: Dictionary) -> void:
	var current_set: Dictionary = _snapshot_brick_set(snap)
	# Brick destructions: idx in _last_brick_set with hp > 0 not in current_set.
	for idx in _last_brick_set.keys():
		if current_set.has(int(idx)):
			continue
		# Brick gone — play break SFX + tier-aware haptic. Look up its value
		# from `level.cells` (parallel to idx).
		var v: int = _brick_value_for(int(idx))
		_play_brick_break_sfx(v)
		var tier: Dictionary = Haptics.tier_for(v, _BRICK_HAPTIC_TIERS)
		Haptics.pulse(float(tier["intensity"]), int(tier["duration_ms"]))
	_last_brick_set = current_set
	# Wall + paddle hits via velocity sign flips. STICKY mode has the ball
	# pinned to the paddle so vy=0 — no sign flips happen.
	var ball: Dictionary = snap.get("ball", {})
	var vx: float = float(ball.get("vx", 0.0))
	var vy: float = float(ball.get("vy", 0.0))
	if int(snap.get("mode", -1)) == BreakoutGameState.Mode.LIVE:
		# vy flipped from positive to negative → paddle hit (ball was falling,
		# now rising). vy flipped from negative to positive → top wall hit.
		if _last_ball_vy > 0.0 and vy < 0.0:
			if _sfx_paddle != null:
				_sfx_paddle.play()
		elif _last_ball_vy < 0.0 and vy > 0.0:
			if _sfx_wall != null:
				_sfx_wall.play()
		# vx sign flip → side wall hit.
		if signf(_last_ball_vx) != signf(vx) and _last_ball_vx != 0.0 and vx != 0.0:
			if _sfx_wall != null:
				_sfx_wall.play()
	_last_ball_vx = vx
	_last_ball_vy = vy


static func _snapshot_brick_set(snap: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var bricks: Array = snap.get("bricks", [])
	for b in bricks:
		out[int(b.get("idx", -1))] = int(b.get("hp", 0))
	return out


func _brick_value_for(idx: int) -> int:
	if level == null:
		return 0
	if idx < 0 or idx >= level.cells.size():
		return 0
	var cell: Variant = level.cells[idx]
	if not (cell is Dictionary):
		return 0
	return int((cell as Dictionary).get("value", 0))


func _play_brick_break_sfx(value: int) -> void:
	if _sfx_brick == null:
		return
	# Pitch maps inversely to value: higher-value bricks ring lower (heavier).
	var v: float = clamp(float(value), 10.0, 500.0)
	var freq: float = 880.0 - v * 0.8
	_sfx_brick.stream = SfxTones.tone_chord([freq, freq * 1.5], 0.08, 0.45)
	_sfx_brick.play()

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
	if not _game_over_sfx_played:
		_game_over_sfx_played = true
		if _sfx_game_over != null:
			_sfx_game_over.play()
	# Persist best for the level the player died on, plus run total.
	_persist_best_at_death()
	var snap: Dictionary = state.snapshot()
	game_over_overlay.show_with(int(snap.get("score", 0)))

func _enter_won() -> void:
	_phase = Phase.WON
	life_lost_overlay.visible = false
	if not _level_clear_sfx_played:
		_level_clear_sfx_played = true
		if _sfx_level_clear != null:
			_sfx_level_clear.play()
		Haptics.pulse(float(_LEVEL_CLEAR_HAPTIC[0]), int(_LEVEL_CLEAR_HAPTIC[1]))
	var snap: Dictionary = state.snapshot()
	_persist_best_at_level_clear(int(snap.get("score", 0)))
	if _level_index < LevelPack.size():
		win_overlay.set_mode(WinOverlay.Mode.LEVEL_CLEAR)
	else:
		win_overlay.set_mode(WinOverlay.Mode.PACK_COMPLETE)
	win_overlay.show_with(int(snap.get("score", 0)))

func _on_next_level_pressed() -> void:
	if state == null:
		return
	# Carry score + lives across the transition (level fresh-create resets them).
	var carry_score: int = state.score
	var carry_lives: int = state.lives
	_level_index += 1
	if _level_index > LevelPack.size():
		# Defensive: pack-complete should hide the Next button.
		_on_restart_pressed()
		return
	_load_level(_level_index, carry_score, carry_lives)

func _on_restart_pressed() -> void:
	game_over_overlay.visible = false
	win_overlay.visible = false
	# Fresh pack run from level 01 with bumped seed for variety.
	_seed = _seed + 1
	_level_index = 1
	_level_score_offset = 0
	_load_level(_level_index, 0, BreakoutConfig.new().lives_start)

func _on_menu_pressed() -> void:
	exit_requested.emit()

func _real_now() -> int:
	return Time.get_ticks_msec()


# --- Persistence (issue #23) ---


## On level-clear, persist `breakout.best.level_NN` if the player's score (the
## *cumulative* run score at clear) beats the stored best. Run-best updates
## here too because clearing a level produces a strictly better run total than
## any prior run that ended sooner.
func _persist_best_at_level_clear(run_score_at_clear: int) -> void:
	if not _has_settings():
		return
	var key: StringName = LevelPack.key_for(_level_index)
	var prior: int = int(Settings.get_value(key, 0))
	if run_score_at_clear > prior:
		Settings.set_value(key, run_score_at_clear)
	var run_prior: int = int(Settings.get_value(BEST_RUN_KEY, 0))
	if run_score_at_clear > run_prior:
		Settings.set_value(BEST_RUN_KEY, run_score_at_clear)


## On game-over, persist run-best only (per-level best updates only on actual
## level clear — dying mid-level doesn't earn a level entry).
func _persist_best_at_death() -> void:
	if not _has_settings() or state == null:
		return
	var s: int = state.score
	var run_prior: int = int(Settings.get_value(BEST_RUN_KEY, 0))
	if s > run_prior:
		Settings.set_value(BEST_RUN_KEY, s)
