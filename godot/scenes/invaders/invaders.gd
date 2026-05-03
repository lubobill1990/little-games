extends Control
## Invaders top-level scene. Wires InputManager → InvadersGameState → view layers.
##
## Implements the GameHost duck-typed contract (start/pause/resume/teardown +
## exit_requested / score_reported signals). Mirrors the breakout/snake/2048
## scene pattern.
##
## Render model: each view layer (formation, bunkers, player, bullets, ufo,
## explosions) is its own Node2D drawing in world units (config.world_w ×
## world_h). The BoardHost Control applies a uniform fit-letterbox transform
## on every viewport resize.
##
## Sub-step time: per the Dev plan, the scene must NOT call state.tick()
## while the wave-cleared interlude is on screen. set_last_tick(now_ms) is
## called on resume / interlude exit / focus-in to prevent the sim from
## auto-stepping the missed wall-clock window.

const InvadersConfig := preload("res://scripts/invaders/core/invaders_config.gd")
const InvadersLevel := preload("res://scripts/invaders/core/invaders_level.gd")
const InvadersGameState := preload("res://scripts/invaders/core/invaders_state.gd")
const Palette := preload("res://scripts/invaders/invaders_palette.gd")
const FormationLayer := preload("res://scenes/invaders/view/formation_layer.gd")
const BunkersLayer := preload("res://scenes/invaders/view/bunkers_layer.gd")
const PlayerLayer := preload("res://scenes/invaders/view/player_layer.gd")
const BulletsLayer := preload("res://scenes/invaders/view/bullets_layer.gd")
const UfoLayer := preload("res://scenes/invaders/view/ufo_layer.gd")
const ExplosionLayer := preload("res://scenes/invaders/view/explosion_layer.gd")
const HUD := preload("res://scenes/invaders/view/hud.gd")
const PauseOverlay := preload("res://scenes/invaders/view/pause_overlay.gd")
const WaveInterlude := preload("res://scenes/invaders/view/wave_interlude.gd")
const GameOverOverlay := preload("res://scenes/invaders/view/game_over_overlay.gd")
const FireButton := preload("res://scenes/invaders/view/fire_button.gd")

# GameHost contract.
signal exit_requested()
signal score_reported(value: int)

const WAVE_INTERLUDE_MS: int = 1200
const TOUCH_DRAG_ZONE_FRACTION: float = 0.6   # left 60% of playfield
const TOUCH_DRAG_LERP_FACTOR: float = 0.35

enum Phase { PLAYING, PAUSED, INTERLUDE, GAME_OVER }

@onready var board_host: Control = $BoardHost
@onready var formation_layer: Node2D = $BoardHost/FormationLayer
@onready var bunkers_layer: Node2D = $BoardHost/BunkersLayer
@onready var player_layer: Node2D = $BoardHost/PlayerLayer
@onready var bullets_layer: Node2D = $BoardHost/BulletsLayer
@onready var ufo_layer: Node2D = $BoardHost/UfoLayer
@onready var explosion_layer: Node2D = $BoardHost/ExplosionLayer
@onready var hud: Control = $HUD
@onready var pause_overlay: CanvasLayer = $PauseOverlay
@onready var wave_interlude: CanvasLayer = $WaveInterlude
@onready var game_over_overlay: CanvasLayer = $GameOverOverlay
@onready var fire_button: Control = $FireButton

var state: InvadersGameState
var config: InvadersConfig
var level: InvadersLevel
var _phase: int = Phase.PLAYING
var _logical_now_ms: int = 0
var _last_real_ms: int = 0
var _started: bool = false
var _last_reported_score: int = -1
var _seed: int = 0

# Wave-interlude (real-time, not core time).
var _interlude_until_real_ms: int = -1
var _last_drawn_wave: int = 1

# Snapshot diff tracking — drives selective layer redraws + score-popup detection.
var _prev_snap: Dictionary = {}
var _last_formation_step_ms: int = 0
var _formation_pose: int = Palette.MARCH_POSE_A
var _last_bunker_hash: int = 0
var _last_ufo_present: bool = false
var _last_ufo_x: float = 0.0
var _last_score: int = 0

# Touch tracking.
var _drag_touch_index: int = -1
var _touch_target_x: float = -1.0   # world coord; -1 = no active drag

# Cached letterbox transform.
var _world_to_local_scale: float = 1.0
var _world_to_local_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	pause_overlay.visible = false
	wave_interlude.visible = false
	game_over_overlay.visible = false
	InputManager.action_pressed.connect(_on_action_pressed)
	game_over_overlay.restart_requested.connect(_on_restart_pressed)
	game_over_overlay.menu_requested.connect(_on_menu_pressed)
	pause_overlay.menu_requested.connect(_on_menu_pressed)
	fire_button.fire_requested.connect(_on_fire_pressed)
	board_host.resized.connect(_recompute_letterbox)
	# Standalone launch: auto-start with deterministic seed 0.
	if get_tree().current_scene == self:
		start(0)


# --- GameHost contract ---

func start(seed_value: int = 0) -> void:
	_seed = seed_value
	config = InvadersConfig.new()
	level = InvadersLevel.new()
	state = InvadersGameState.create(_seed, config, level)
	if state == null:
		push_error("Invaders: failed to create state (tunneling cap?)")
		return
	_phase = Phase.PLAYING
	_logical_now_ms = 0
	_last_real_ms = _real_now()
	_last_reported_score = -1
	_interlude_until_real_ms = -1
	_drag_touch_index = -1
	_touch_target_x = -1.0
	_prev_snap = state.snapshot()
	_last_drawn_wave = int(_prev_snap.get("wave", 1))
	_last_formation_step_ms = int((_prev_snap.get("formation", {}) as Dictionary).get("last_step_ms", 0))
	_formation_pose = Palette.MARCH_POSE_A
	_last_bunker_hash = _hash_bunkers(_prev_snap)
	_last_ufo_present = _prev_snap.get("ufo", null) != null
	_last_ufo_x = float((_prev_snap.get("ufo", {}) as Dictionary).get("x", 0.0)) if _last_ufo_present else 0.0
	_last_score = int(_prev_snap.get("score", 0))
	_configure_layers()
	pause_overlay.visible = false
	wave_interlude.visible = false
	game_over_overlay.visible = false
	_started = true
	_recompute_letterbox()
	_redraw_all(_prev_snap)


func pause() -> void:
	if _phase == Phase.PLAYING:
		_phase = Phase.PAUSED
		pause_overlay.visible = true


func resume() -> void:
	if _phase == Phase.PAUSED:
		_phase = Phase.PLAYING
		pause_overlay.visible = false
		_last_real_ms = _real_now()
		# Don't auto-step the missed wall-clock window.
		if state != null:
			state.set_last_tick(_logical_now_ms)


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
	if _phase == Phase.PAUSED or _phase == Phase.GAME_OVER:
		return
	# Wave-cleared interlude: render the current snapshot but DO NOT call tick.
	if _phase == Phase.INTERLUDE:
		if real_now >= _interlude_until_real_ms:
			_phase = Phase.PLAYING
			wave_interlude.visible = false
			# Re-anchor sim so it doesn't auto-step the interlude window.
			state.set_last_tick(_logical_now_ms + dt)
		_logical_now_ms += dt
		return
	_logical_now_ms += dt
	# Compute player intent from input + touch.
	var intent_x: float = _compute_player_intent_norm()
	state.set_player_intent(intent_x * config.player_max_speed_px_s)
	var changed: bool = state.tick(_logical_now_ms)
	if changed:
		_update_views()
	if state.is_game_over() and _phase != Phase.GAME_OVER:
		_enter_game_over()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_last_real_ms = _real_now()
		if state != null and (_phase == Phase.PLAYING or _phase == Phase.INTERLUDE):
			state.set_last_tick(_logical_now_ms)


# --- Player intent ---

func _compute_player_intent_norm() -> float:
	# Touch drag overrides if active.
	if _touch_target_x >= 0.0 and state != null:
		var dx: float = _touch_target_x - state.player_x
		if absf(dx) < 0.5:
			return 0.0
		return clampf(dx / config.player_max_speed_px_s * 2.0, -1.0, 1.0)
	var right: float = Input.get_action_strength(&"move_right")
	var left: float = Input.get_action_strength(&"move_left")
	return clampf(right - left, -1.0, 1.0)


# --- View ---

func _configure_layers() -> void:
	formation_layer.configure(config, level)
	bunkers_layer.configure(config, level)
	player_layer.configure(config)
	bullets_layer.configure(config)
	ufo_layer.configure(config)
	explosion_layer.configure(config)
	hud.configure(config)


func _redraw_all(snap: Dictionary) -> void:
	formation_layer.update_from_snapshot(snap, _formation_pose)
	bunkers_layer.update_from_snapshot(snap)
	player_layer.update_from_snapshot(snap)
	bullets_layer.update_from_snapshot(snap)
	ufo_layer.update_from_snapshot(snap)
	hud.update_from_snapshot(snap)


func _update_views() -> void:
	if state == null:
		return
	var snap: Dictionary = state.snapshot()
	# Wave change → trigger interlude before letting the next-wave snapshot animate.
	var wave: int = int(snap.get("wave", 1))
	if wave != _last_drawn_wave:
		_last_drawn_wave = wave
		_enter_wave_interlude(wave)
	# Formation step?
	var fm: Dictionary = snap.get("formation", {})
	var step_ms: int = int(fm.get("last_step_ms", 0))
	# `last_step_ms` is set to set_last_tick on initialize/wave/resume, so we
	# explicitly toggle pose on a real formation cell motion: detect via the
	# sub-step accumulator change indirectly — easier: detect via formation
	# origin change OR live_mask change. Snapshot ox/oy + dir together.
	var prev_fm: Dictionary = _prev_snap.get("formation", {})
	var formation_moved: bool = (
		fm.get("ox", 0.0) != prev_fm.get("ox", 0.0)
		or fm.get("oy", 0.0) != prev_fm.get("oy", 0.0)
		or fm.get("dir", 0) != prev_fm.get("dir", 0)
	)
	# Enemy mask change forces formation redraw too (kill animation).
	var enemy_mask_changed: bool = not _packed_byte_eq(snap.get("enemies", PackedByteArray()), _prev_snap.get("enemies", PackedByteArray()))
	if formation_moved:
		_formation_pose = Palette.MARCH_POSE_B if _formation_pose == Palette.MARCH_POSE_A else Palette.MARCH_POSE_A
		formation_layer.update_from_snapshot(snap, _formation_pose)
	elif enemy_mask_changed:
		formation_layer.update_from_snapshot(snap, _formation_pose)
	_last_formation_step_ms = step_ms
	# Bunkers redraw on diff.
	var bhash: int = _hash_bunkers(snap)
	if bhash != _last_bunker_hash:
		_last_bunker_hash = bhash
		bunkers_layer.update_from_snapshot(snap)
	# Player + bullets redraw every frame (cheap).
	player_layer.update_from_snapshot(snap)
	bullets_layer.update_from_snapshot(snap)
	# UFO + score popup.
	var ufo_present: bool = snap.get("ufo", null) != null
	var score: int = int(snap.get("score", 0))
	if ufo_present != _last_ufo_present or ufo_present:
		ufo_layer.update_from_snapshot(snap)
	# UFO killed this tick = ufo went null AND score increased: scene-only popup.
	if _last_ufo_present and not ufo_present and score > _last_score:
		ufo_layer.spawn_score_popup(_last_ufo_x, score - _last_score)
	if ufo_present:
		_last_ufo_x = float((snap.get("ufo", {}) as Dictionary).get("x", _last_ufo_x))
	_last_ufo_present = ufo_present
	_last_score = score
	hud.update_from_snapshot(snap)
	_prev_snap = snap
	if score != _last_reported_score:
		_last_reported_score = score
		score_reported.emit(score)


static func _packed_byte_eq(a: Variant, b: Variant) -> bool:
	if not (a is PackedByteArray) or not (b is PackedByteArray):
		return false
	var pa: PackedByteArray = a
	var pb: PackedByteArray = b
	if pa.size() != pb.size():
		return false
	for i in range(pa.size()):
		if pa[i] != pb[i]:
			return false
	return true


static func _hash_bunkers(snap: Dictionary) -> int:
	# Cheap rolling hash over each bunker's PackedByteArray. Cells flip rarely
	# (only on bullet hit), so any change reliably moves the hash.
	var bgs: Array = snap.get("bunkers", [])
	var h: int = 0x12345678
	for bg in bgs:
		if bg is PackedByteArray:
			var pa: PackedByteArray = bg
			# Hash by xor'ing every 4-byte chunk into h. Cheap and good enough.
			var i: int = 0
			while i < pa.size():
				var w: int = pa[i]
				if i + 1 < pa.size(): w |= pa[i + 1] << 8
				if i + 2 < pa.size(): w |= pa[i + 2] << 16
				if i + 3 < pa.size(): w |= pa[i + 3] << 24
				h = ((h << 5) | (h >> 27)) ^ w
				i += 4
	return h


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
	for layer in [formation_layer, bunkers_layer, player_layer, bullets_layer, ufo_layer, explosion_layer]:
		if layer != null:
			layer.position = off
			layer.scale = Vector2(s, s)


func _local_to_world(local: Vector2) -> Vector2:
	if _world_to_local_scale <= 0.0:
		return Vector2.ZERO
	return (local - _world_to_local_offset) / _world_to_local_scale


# --- Input: action signals ---

func _on_action_pressed(action: StringName) -> void:
	if action == &"pause":
		_toggle_pause()
		return
	if _phase != Phase.PLAYING:
		return
	if state == null:
		return
	if action == &"fire":
		state.fire()


func _on_fire_pressed() -> void:
	if _phase != Phase.PLAYING or state == null:
		return
	state.fire()


# --- Input: touch (drag zone in left 60% of playfield) ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)


func _handle_touch(t: InputEventScreenTouch) -> void:
	if _phase != Phase.PLAYING:
		return
	var w: Vector2 = _local_to_world(board_host.to_local(t.position))
	var in_drag_zone: bool = w.x >= 0.0 and w.x <= config.world_w * TOUCH_DRAG_ZONE_FRACTION \
			and w.y >= 0.0 and w.y <= config.world_h
	if t.pressed:
		if _drag_touch_index == -1 and in_drag_zone:
			_drag_touch_index = t.index
			_touch_target_x = clampf(w.x, 0.0, config.world_w)
	else:
		if t.index == _drag_touch_index:
			_drag_touch_index = -1
			_touch_target_x = -1.0


func _handle_drag(d: InputEventScreenDrag) -> void:
	if d.index != _drag_touch_index:
		return
	if _phase != Phase.PLAYING:
		return
	var w: Vector2 = _local_to_world(board_host.to_local(d.position))
	_touch_target_x = clampf(w.x, 0.0, config.world_w)


# --- Phase transitions ---

func _toggle_pause() -> void:
	if _phase == Phase.PLAYING:
		pause()
	elif _phase == Phase.PAUSED:
		resume()


func _enter_wave_interlude(new_wave: int) -> void:
	_phase = Phase.INTERLUDE
	wave_interlude.show_with(new_wave)
	_interlude_until_real_ms = _real_now() + WAVE_INTERLUDE_MS


func _enter_game_over() -> void:
	_phase = Phase.GAME_OVER
	wave_interlude.visible = false
	var snap: Dictionary = state.snapshot() if state != null else {}
	game_over_overlay.show_with(int(snap.get("score", 0)), int(snap.get("wave", 1)))


func _on_restart_pressed() -> void:
	game_over_overlay.visible = false
	# Bump seed for variety on retry.
	_seed = _seed + 1
	start(_seed)


func _on_menu_pressed() -> void:
	exit_requested.emit()


func _real_now() -> int:
	return Time.get_ticks_msec()


# --- Test seam ---

## Force a snapshot redraw bypass; used by scene tests to assert layer state
## after directly mutating `state` outside the normal _process loop.
func _refresh_views_for_test() -> void:
	if state == null:
		return
	_prev_snap = state.snapshot()
	_redraw_all(_prev_snap)
