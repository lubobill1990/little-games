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
const SfxTones := preload("res://scripts/core/audio/sfx_tones.gd")
const SfxVolume := preload("res://scripts/core/audio/sfx_volume.gd")
const Haptics := preload("res://scripts/core/input/haptics.gd")

# GameHost contract.
signal exit_requested()
signal score_reported(value: int)

const WAVE_INTERLUDE_MS: int = 1200
const TOUCH_DRAG_ZONE_FRACTION: float = 0.6   # left 60% of playfield
const TOUCH_DRAG_LERP_FACTOR: float = 0.35

# Persistence key per docs/persistence.md.
const BEST_KEY: StringName = &"invaders.best"

# Four-tone formation march (acceptance #2). Cycle by step_index % 4.
const _STEP_TONE_FREQS: Array[float] = [196.0, 175.0, 147.0, 131.0]   # G3/F3/D3/C3
const _STEP_TONE_DUR: float = 0.06

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
var _last_lives: int = 0
var _game_over_sfx_played: bool = false

# Audio dispatcher — duck-typed so tests can inject a recorder. Set in _ready();
# replace via _inject_audio() before start() in tests. Mirrors tetris's pattern.
# Required interface: play(StringName), stop(StringName).
var _audio: Object

# Per-event AudioStreamPlayer cache. step tones are pre-baked at _ready().
var _sfx_players: Dictionary = {}
var _ufo_loop_player: AudioStreamPlayer
var _ufo_loop_active: bool = false
var _ufo_fade_tween: Tween

# Step-tone cycle index (0..3 → tones 1..4). Reset on start() and game-over.
var _step_index: int = 0

# Best score, loaded at start() from Settings if present.
var _best_score: int = 0

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
	_setup_sfx()
	# Default audio sink is `self` — _audio.play(key) calls _play_sfx_key(key).
	# Tests can override by calling _inject_audio(recorder) before start().
	if _audio == null:
		_audio = self
	InputManager.action_pressed.connect(_on_action_pressed)
	game_over_overlay.restart_requested.connect(_on_restart_pressed)
	game_over_overlay.menu_requested.connect(_on_menu_pressed)
	pause_overlay.menu_requested.connect(_on_menu_pressed)
	fire_button.fire_requested.connect(_on_fire_pressed)
	board_host.resized.connect(_recompute_letterbox)
	if _has_settings():
		Settings.changed.connect(_on_settings_changed)
		_apply_sfx_volume()
	# Standalone launch: auto-start with deterministic seed 0.
	if get_tree().current_scene == self:
		start(0)


# --- Audio setup (procedural tones; no asset files) ---

func _setup_sfx() -> void:
	# Pre-bake the four step tones + one-shot keys; cheap (< 0.5 KiB each).
	for i in 4:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.stream = SfxTones.tone(_STEP_TONE_FREQS[i], _STEP_TONE_DUR, 0.35)
		add_child(p)
		_sfx_players[StringName("step_%d" % (i + 1))] = p
	_register_oneshot(&"fire", SfxTones.tone(720.0, 0.05, 0.4))
	_register_oneshot(&"explode_enemy", SfxTones.tone_sequence([
		Vector2(220.0, 0.06), Vector2(110.0, 0.10),
	], 0.45))
	_register_oneshot(&"explode_player", SfxTones.tone_sequence([
		Vector2(180.0, 0.10), Vector2(120.0, 0.18), Vector2(80.0, 0.30),
	], 0.55))
	_register_oneshot(&"ufo_kill", SfxTones.tone_sequence([
		Vector2(660.0, 0.06), Vector2(880.0, 0.06), Vector2(1320.0, 0.10),
	], 0.5))
	_register_oneshot(&"wave_clear", SfxTones.tone_sequence([
		Vector2(523.0, 0.08), Vector2(659.0, 0.08), Vector2(784.0, 0.16),
	], 0.5))
	_register_oneshot(&"game_over", SfxTones.tone_sequence([
		Vector2(330.0, 0.12), Vector2(247.0, 0.18), Vector2(165.0, 0.30),
	], 0.55))
	# UFO loop player: a sine warble, looping. We retrigger on each "start".
	_ufo_loop_player = AudioStreamPlayer.new()
	var loop_stream: AudioStreamWAV = SfxTones.tone(420.0, 0.30, 0.30)
	loop_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop_stream.loop_end = loop_stream.data.size() / 2
	_ufo_loop_player.stream = loop_stream
	add_child(_ufo_loop_player)


func _register_oneshot(key: StringName, stream: AudioStreamWAV) -> void:
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
	if _ufo_loop_player != null:
		SfxVolume.set_player_volume(_ufo_loop_player, v)


func _on_settings_changed(key: StringName) -> void:
	var s: String = String(key)
	if s == "audio.master" or s == "audio.sfx":
		_apply_sfx_volume()


## Default audio sink. `_audio.play(key)` lands here unless a test injected a
## recorder. Looks up the cached AudioStreamPlayer and replays it.
func play(key: StringName) -> void:
	_play_sfx_key(key)


func stop(key: StringName) -> void:
	if key == &"ufo_loop":
		_stop_ufo_loop_with_fade()


func _play_sfx_key(key: StringName) -> void:
	if key == &"ufo_loop":
		_start_ufo_loop()
		return
	var p: AudioStreamPlayer = _sfx_players.get(key, null)
	if p != null:
		p.stop()
		p.play()


func _start_ufo_loop() -> void:
	if _ufo_loop_player == null:
		return
	if _ufo_fade_tween != null and _ufo_fade_tween.is_valid():
		_ufo_fade_tween.kill()
	_ufo_loop_player.volume_db = 0.0
	if not _ufo_loop_player.playing:
		_ufo_loop_player.play()
	_ufo_loop_active = true


func _stop_ufo_loop_with_fade() -> void:
	if _ufo_loop_player == null or not _ufo_loop_active:
		return
	_ufo_loop_active = false
	if _ufo_fade_tween != null and _ufo_fade_tween.is_valid():
		_ufo_fade_tween.kill()
	_ufo_fade_tween = create_tween()
	_ufo_fade_tween.tween_property(_ufo_loop_player, "volume_db", -40.0, 0.08)
	_ufo_fade_tween.tween_callback(Callable(_ufo_loop_player, "stop"))


## Replace the SFX dispatcher (tests inject a recorder before start()). The
## recorder must implement `play(StringName)` and `stop(StringName)`.
func _inject_audio(audio: Object) -> void:
	_audio = audio


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
	_last_lives = int(_prev_snap.get("lives", 0))
	_step_index = 0
	_game_over_sfx_played = false
	if _ufo_loop_active:
		_stop_ufo_loop_with_fade()
	_best_score = int(Settings.get_value(BEST_KEY, 0)) if _has_settings() else 0
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
	hud.update_from_snapshot(snap, _best_score)


func _update_views() -> void:
	if state == null:
		return
	var snap: Dictionary = state.snapshot()
	# Wave change → trigger interlude before letting the next-wave snapshot animate.
	var wave: int = int(snap.get("wave", 1))
	var wave_just_changed: bool = wave != _last_drawn_wave
	if wave_just_changed:
		_last_drawn_wave = wave
		_enter_wave_interlude(wave)
	# Audio dispatch sits between core diff and view update. The interlude flag
	# is taken from the phase the scene will sit in *during this tick*; if a
	# wave just incremented, _enter_wave_interlude flipped phase to INTERLUDE
	# above, so step-tones for this very tick are suppressed (acceptance #6).
	_audio_dispatch(_prev_snap, snap, _phase == Phase.INTERLUDE)
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
	_last_lives = int(snap.get("lives", _last_lives))
	hud.update_from_snapshot(snap, _best_score)
	_prev_snap = snap
	if score != _last_reported_score:
		_last_reported_score = score
		score_reported.emit(score)


# --- Audio dispatcher (snapshot diff → sfx/haptic events) ---

## Pure dispatcher. Compares prev/curr snapshots and routes events to `_audio`
## (duck-typed: tests inject a recorder). `in_interlude` suppresses step tones.
##
## Acceptance map (issue #29):
##   #2 four-tone cycle: step_<i % 4 + 1> per formation step, scene-local idx.
##   #3 fire haptic only on accepted shot (player_bullet 0→1).
##   #5 ufo_loop start on null→present, fade-stop on present→null. ufo_kill
##     jingle only when score went up the same tick.
##   #6 no step-tone during interlude (caller passes `in_interlude=true`).
func _audio_dispatch(prev: Dictionary, curr: Dictionary, in_interlude: bool) -> void:
	if _audio == null:
		return
	# Formation step → step tone (skipped during interlude).
	if not in_interlude:
		var prev_fm: Dictionary = prev.get("formation", {})
		var curr_fm: Dictionary = curr.get("formation", {})
		var moved: bool = (
			curr_fm.get("ox", 0.0) != prev_fm.get("ox", 0.0)
			or curr_fm.get("oy", 0.0) != prev_fm.get("oy", 0.0)
			or curr_fm.get("dir", 0) != prev_fm.get("dir", 0)
		)
		if moved:
			var key := StringName("step_%d" % (_step_index % 4 + 1))
			_audio.call(&"play", key)
			_step_index += 1
	# Player bullet 0→1 (accepted fire).
	var prev_pb: Dictionary = prev.get("player_bullet", {})
	var curr_pb: Dictionary = curr.get("player_bullet", {})
	if not bool(prev_pb.get("alive", false)) and bool(curr_pb.get("alive", false)):
		_audio.call(&"play", &"fire")
		Haptics.pulse(0.3, 40)
	# Enemy mask: bits cleared since prev → explode_enemy per loss.
	var pe: Variant = prev.get("enemies", null)
	var ce: Variant = curr.get("enemies", null)
	if pe is PackedByteArray and ce is PackedByteArray:
		var lost: int = _enemies_lost(pe, ce)
		for _i in lost:
			_audio.call(&"play", &"explode_enemy")
	# Lives drop → explode_player + haptic.
	var prev_lives: int = int(prev.get("lives", _last_lives))
	var curr_lives: int = int(curr.get("lives", _last_lives))
	if curr_lives < prev_lives:
		_audio.call(&"play", &"explode_player")
		Haptics.pulse(0.7, 250)
	# UFO transitions.
	var prev_ufo_present: bool = prev.get("ufo", null) != null
	var curr_ufo_present: bool = curr.get("ufo", null) != null
	if not prev_ufo_present and curr_ufo_present:
		_audio.call(&"play", &"ufo_loop")
	elif prev_ufo_present and not curr_ufo_present:
		_audio.call(&"stop", &"ufo_loop")
		# Score increased on the same tick → killed (vs flew off-screen).
		var prev_score: int = int(prev.get("score", 0))
		var curr_score: int = int(curr.get("score", 0))
		if curr_score > prev_score:
			_audio.call(&"play", &"ufo_kill")
			Haptics.pulse(0.4, 120)
	# Wave change.
	var prev_wave: int = int(prev.get("wave", 1))
	var curr_wave: int = int(curr.get("wave", 1))
	if curr_wave > prev_wave:
		_audio.call(&"play", &"wave_clear")


static func _enemies_lost(prev: PackedByteArray, curr: PackedByteArray) -> int:
	var n: int = mini(prev.size(), curr.size())
	var lost: int = 0
	for i in range(n):
		if prev[i] == 1 and curr[i] == 0:
			lost += 1
	return lost


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
	if _ufo_loop_active:
		_stop_ufo_loop_with_fade()
	if not _game_over_sfx_played:
		_game_over_sfx_played = true
		if _audio != null:
			_audio.call(&"play", &"game_over")
	_persist_best_at_death()
	var snap: Dictionary = state.snapshot() if state != null else {}
	game_over_overlay.show_with(int(snap.get("score", 0)), int(snap.get("wave", 1)), _best_score)


func _persist_best_at_death() -> void:
	if not _has_settings() or state == null:
		return
	var s: int = state.score
	var prior: int = int(Settings.get_value(BEST_KEY, 0))
	if s > prior:
		Settings.set_value(BEST_KEY, s)
		_best_score = s


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
