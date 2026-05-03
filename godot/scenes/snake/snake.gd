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
const StartScreen := preload("res://scenes/snake/view/start_screen.gd")
const Difficulty := preload("res://scripts/snake/difficulty.gd")
const SfxTones := preload("res://scripts/core/audio/sfx_tones.gd")
const SfxVolume := preload("res://scripts/core/audio/sfx_volume.gd")
const Haptics := preload("res://scripts/core/input/haptics.gd")

# GameHost contract.
signal exit_requested()
signal score_reported(value: int)

# Touch swipe threshold (px). Smaller swipes are ignored.
const SWIPE_MIN_PX: float = 24.0

# Haptic intensities (intensity 0..1, duration ms) — eat = quick, death = long.
const _EAT_HAPTIC: Array = [0.3, 80]
const _GAME_OVER_HAPTIC: Array = [0.7, 250]

enum Phase { PICKING, PLAYING, PAUSED, GAME_OVER }

@onready var board: Node2D = $HBox/BoardHost/Board
@onready var hud: VBoxContainer = $HBox/Side/HUD
@onready var pause_overlay: CanvasLayer = $PauseOverlay
@onready var game_over_overlay: CanvasLayer = $GameOverOverlay
@onready var start_screen: CanvasLayer = $StartScreen

var state: SnakeGameState
var config: SnakeConfig
var _phase: int = Phase.PICKING
var _logical_now_ms: int = 0
var _last_real_ms: int = 0
var _started: bool = false
var _last_reported_score: int = -1
var _seed: int = 0
var _difficulty_id: String = Difficulty.DEFAULT_ID
var _best_score: int = 0

# SFX players keyed by event name; populated by _setup_sfx.
var _sfx_players: Dictionary = {}
# Default audio sink is `self`; tests override via _inject_audio.
var _audio: Object

# Snapshot diff tracking for audio dispatch.
var _last_score: int = 0
var _last_level: int = 1
var _last_game_over: bool = false

# Touch swipe tracking. -1 = no active touch.
var _touch_index: int = -1
var _touch_start: Vector2 = Vector2.ZERO

func _ready() -> void:
	pause_overlay.visible = false
	game_over_overlay.visible = false
	_setup_sfx()
	if _audio == null:
		_audio = self
	InputManager.action_pressed.connect(_on_action_pressed)
	InputManager.action_repeated.connect(_on_action_repeated)
	game_over_overlay.restart_requested.connect(_on_restart_pressed)
	game_over_overlay.menu_requested.connect(_on_menu_pressed)
	pause_overlay.menu_requested.connect(_on_menu_pressed)
	start_screen.difficulty_chosen.connect(_on_difficulty_chosen)
	if _has_settings():
		Settings.changed.connect(_on_settings_changed)
		_apply_sfx_volume()
	# Standalone launch (project main_scene == us; or scene loaded directly in
	# a test). Show difficulty picker; tests bypass via start().
	if get_tree().current_scene == self:
		_show_difficulty_picker()

# --- GameHost contract ---

func start(seed_value: int = 0, difficulty_id: String = "") -> void:
	_seed = seed_value
	if difficulty_id == "":
		difficulty_id = _difficulty_id
	_difficulty_id = difficulty_id
	var d: Dictionary = Difficulty.by_id(_difficulty_id)
	config = SnakeConfig.new()
	config.start_step_ms = int(d["start_step_ms"])
	config.walls = bool(d["walls"])
	state = SnakeGameState.create(_seed, config)
	board.configure(config.grid_w, config.grid_h, config.walls)
	hud.set_difficulty(String(d["title"]))
	_phase = Phase.PLAYING
	_logical_now_ms = 0
	_last_real_ms = _real_now()
	_last_reported_score = -1
	_last_score = 0
	_last_level = 1
	_last_game_over = false
	_best_score = int(Settings.get_value(Difficulty.best_key(_difficulty_id), 0)) if _has_settings() else 0
	pause_overlay.visible = false
	game_over_overlay.visible = false
	if start_screen != null:
		start_screen.visible = false
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
	_audio_dispatch(snap)
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
	_persist_best()
	var snap: Dictionary = state.snapshot()
	game_over_overlay.show_with(int(snap.get("score", 0)), int(snap.get("level", 1)), _best_score)

func _on_restart_pressed() -> void:
	game_over_overlay.visible = false
	# Fresh seed for replay; keep the same difficulty.
	start(_seed + 1, _difficulty_id)

func _on_menu_pressed() -> void:
	exit_requested.emit()

func _real_now() -> int:
	return Time.get_ticks_msec()


# --- Audio (procedural tones; no asset files) ---

func _setup_sfx() -> void:
	_register_oneshot(&"eat", SfxTones.tone_sequence([
		Vector2(660.0, 0.04), Vector2(880.0, 0.06),
	], 0.4))
	_register_oneshot(&"level_up", SfxTones.tone_sequence([
		Vector2(523.0, 0.06), Vector2(659.0, 0.06), Vector2(784.0, 0.10),
	], 0.45))
	_register_oneshot(&"game_over", SfxTones.tone_sequence([
		Vector2(330.0, 0.10), Vector2(247.0, 0.16), Vector2(165.0, 0.28),
	], 0.5))


func _register_oneshot(key: StringName, stream: AudioStream) -> void:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	_sfx_players[key] = p


func _has_settings() -> bool:
	return get_tree().root.has_node("Settings")


func _apply_sfx_volume() -> void:
	if not _has_settings():
		return
	var master: float = float(Settings.get_value(&"audio.master", 1.0))
	var sfx: float = float(Settings.get_value(&"audio.sfx", 1.0))
	var v: float = SfxVolume.linear_volume(master, sfx)
	for p in _sfx_players.values():
		if p != null:
			SfxVolume.set_player_volume(p, v)


func _on_settings_changed(key: StringName) -> void:
	var s: String = String(key)
	if s == "audio.master" or s == "audio.sfx":
		_apply_sfx_volume()


## Default audio sink: `_audio.play(key)` lands here unless a test injects a
## recorder via `_inject_audio` before start().
func play(key: StringName) -> void:
	var p: AudioStreamPlayer = _sfx_players.get(key, null)
	if p != null:
		p.stop()
		p.play()


## Test seam: replace the SFX dispatcher with a recorder. Recorder must
## implement `play(StringName)`.
func _inject_audio(audio: Object) -> void:
	_audio = audio


## Compare current snapshot against last; route audio + haptic events.
## Acceptance #1: each gameplay event listed under SFX produces an audible cue.
## Acceptance #2: eat triggers a haptic pulse.
func _audio_dispatch(snap: Dictionary) -> void:
	var s: int = int(snap.get("score", 0))
	var lvl: int = int(snap.get("level", 1))
	var go: bool = bool(snap.get("game_over", false))
	if s > _last_score:
		_audio.play(&"eat")
		Haptics.pulse(float(_EAT_HAPTIC[0]), int(_EAT_HAPTIC[1]))
	if lvl > _last_level:
		_audio.play(&"level_up")
	if go and not _last_game_over:
		_audio.play(&"game_over")
		Haptics.pulse(float(_GAME_OVER_HAPTIC[0]), int(_GAME_OVER_HAPTIC[1]))
	_last_score = s
	_last_level = lvl
	_last_game_over = go


# --- Persistence ---

func _persist_best() -> void:
	if not _has_settings() or state == null:
		return
	var key: StringName = Difficulty.best_key(_difficulty_id)
	var s: int = int(state.snapshot().get("score", 0))
	var prior: int = int(Settings.get_value(key, 0))
	if s > prior:
		Settings.set_value(key, s)
		_best_score = s


# --- Difficulty picker ---

func _show_difficulty_picker() -> void:
	_phase = Phase.PICKING
	_started = false
	pause_overlay.visible = false
	game_over_overlay.visible = false
	var initial: String = Difficulty.DEFAULT_ID
	if _has_settings():
		initial = String(Settings.get_value(Difficulty.LAST_KEY, Difficulty.DEFAULT_ID))
	start_screen.show_picker(initial)


func _on_difficulty_chosen(id: String) -> void:
	_difficulty_id = id
	if _has_settings():
		Settings.set_value(Difficulty.LAST_KEY, id)
	start(0, id)


# --- Test seam ---

func _refresh_views_for_test() -> void:
	if state == null:
		return
	_update_views()
