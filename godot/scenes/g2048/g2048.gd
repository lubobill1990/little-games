extends Control
## 2048 top-level scene. Wires InputManager → Game2048State → tile renderers
## via plan-driven tween animations, with a buffer-1 input gate. Implements
## the GameHost contract used by the menu (start/pause/resume/teardown +
## exit_requested / score_reported signals). Mirrors scenes/snake/snake.gd.
##
## Plan-driven model:
##  1. Direction press → state.plan(dir).
##  2. If plan is empty, gate stays open, no animation, no spawn (acceptance #7).
##  3. Otherwise: close gate, animate every TileMove for ~120 ms.
##     - Slider: just slides to to_cell.
##     - Merge survivor: slides to to_cell; on settle, value updates + pop.
##     - Merge dier: slides to to_cell, then hides (returned to pool).
##  4. state.commit(plan) is called UPFRONT so spawn id is determined; the
##     spawned tile's id is detected as "in state but not in our mirror" and
##     gets a fade-in animation.
##  5. After all animations complete, gate opens. If a buffered direction is
##     present, replay it on the next process tick.

const Game2048Config := preload("res://scripts/g2048/core/g2048_config.gd")
const Game2048State := preload("res://scripts/g2048/core/g2048_state.gd")
const Planner := preload("res://scripts/g2048/core/g2048_planner.gd")
const TileScript := preload("res://scenes/g2048/view/tile.gd")
const Palette := preload("res://scripts/g2048/tile_palette.gd")
const SfxTones := preload("res://scripts/core/audio/sfx_tones.gd")
const SfxVolume := preload("res://scripts/core/audio/sfx_volume.gd")
const Haptics := preload("res://scripts/core/input/haptics.gd")

const BEST_KEY: StringName = &"g2048.best"

# Haptic tier table per Dev plan: (value_threshold, intensity, duration_ms).
# First row whose merged value is < threshold wins; last row is the cap.
const _HAPTIC_TIERS: Array = [
	[16,    0.2,  60],
	[128,   0.4, 100],
	[1024,  0.6, 140],
	[INF,   0.9, 200],
]

# GameHost contract.
signal exit_requested()
signal score_reported(value: int)

# Touch swipe threshold (px). Smaller swipes are ignored.
const SWIPE_MIN_PX: float = 24.0

# Tween durations, mirrored to TileScript defaults.
const SLIDE_MS: int = 120

# Cell pixel size (logical units inside the board Node2D).
const CELL_PX: float = 80.0
const GAP_PX: float = 6.0

enum Phase { PLAYING, WON_CONTINUING, GAME_OVER }

@onready var board_root: Node2D = $HBox/BoardHost/Board
@onready var grid_view: Node2D = $HBox/BoardHost/Board/Grid
@onready var tiles_root: Node2D = $HBox/BoardHost/Board/Tiles
@onready var hud: VBoxContainer = $HBox/Side/HUD
@onready var pause_overlay: CanvasLayer = $PauseOverlay
@onready var game_over_overlay: CanvasLayer = $GameOverOverlay
@onready var win_overlay: CanvasLayer = $WinOverlay

var state: Game2048State
var config: Game2048Config
var _phase: int = Phase.PLAYING
var _started: bool = false
var _seed: int = 0
var _last_reported_score: int = -1

# Tile mirror: id → Tile node. Pool grows as needed; tiles hide rather than
# free when they die so we never leak nodes mid-session.
var _tile_nodes: Dictionary = {}
var _tile_pool: Array = []   # hidden TileScript instances ready for reuse

# Animation gate. Closed while any tile is animating; opens when all settle.
var _input_gate_open: bool = true
# One-deep buffer for the most recent direction press during the gate. -1 = none.
var _buffered_dir: int = -1

# True iff the win overlay has fired this session. Acceptance #5: it shows
# at most once even if `is_won()` stays true.
var _win_shown: bool = false

# Touch swipe tracking.
var _touch_index: int = -1
var _touch_start: Vector2 = Vector2.ZERO

# Polish state (issue #21): undo + sfx + best.
# `_last_snapshot` holds the pre-commit state.snapshot() captured immediately
# before each successful state.commit(). Empty Dictionary == no undo available.
var _last_snapshot: Dictionary = {}
var _best_score: int = 0
# Once the player has won (reached the target tile), don't replay the jingle
# every move — cap to one play per session.
var _2048_sfx_played: bool = false

# SFX players. Created in _ready, streams cached.
var _sfx_slide: AudioStreamPlayer
var _sfx_merge: AudioStreamPlayer
var _sfx_2048: AudioStreamPlayer
var _sfx_over: AudioStreamPlayer


func _ready() -> void:
	pause_overlay.visible = false
	game_over_overlay.visible = false
	win_overlay.visible = false
	_setup_sfx()
	InputManager.action_pressed.connect(_on_action_pressed)
	game_over_overlay.restart_requested.connect(_on_restart_pressed)
	game_over_overlay.menu_requested.connect(_on_menu_pressed)
	pause_overlay.menu_requested.connect(_on_menu_pressed)
	win_overlay.continue_requested.connect(_on_continue_pressed)
	win_overlay.menu_requested.connect(_on_menu_pressed)
	hud.undo_pressed.connect(_on_undo_invoked)
	if _has_settings():
		Settings.changed.connect(_on_settings_changed)
		_apply_sfx_volume()
	# Standalone launch (project main scene == us, or scene loaded directly
	# in a test). Tests override state via start() afterwards.
	if get_tree().current_scene == self:
		start(0)


func _setup_sfx() -> void:
	_sfx_slide = AudioStreamPlayer.new()
	_sfx_slide.stream = SfxTones.tone(220.0, 0.06, 0.4)
	add_child(_sfx_slide)
	_sfx_merge = AudioStreamPlayer.new()
	# Merge stream is replaced per-event with a freshly-tuned tone (tier-aware).
	add_child(_sfx_merge)
	_sfx_2048 = AudioStreamPlayer.new()
	_sfx_2048.stream = SfxTones.tone_sequence([
		Vector2(523.0, 0.10),
		Vector2(659.0, 0.10),
		Vector2(784.0, 0.16),
	])
	add_child(_sfx_2048)
	_sfx_over = AudioStreamPlayer.new()
	_sfx_over.stream = SfxTones.tone_sequence([
		Vector2(330.0, 0.12),
		Vector2(247.0, 0.18),
		Vector2(165.0, 0.30),
	])
	add_child(_sfx_over)


func _has_settings() -> bool:
	return get_tree().root.has_node("Settings")


func _apply_sfx_volume() -> void:
	if not _has_settings():
		return
	var master: float = float(Settings.get_value(&"audio.master", 1.0))
	var sfx: float = float(Settings.get_value(&"audio.sfx", 1.0))
	var v: float = SfxVolume.linear_volume(master, sfx)
	for p in [_sfx_slide, _sfx_merge, _sfx_2048, _sfx_over]:
		if p != null:
			SfxVolume.set_player_volume(p, v)


func _on_settings_changed(key: StringName) -> void:
	var s: String = String(key)
	if s == "audio.master" or s == "audio.sfx":
		_apply_sfx_volume()


# --- GameHost contract ---


func start(seed_value: int = 0) -> void:
	_seed = seed_value
	config = Game2048Config.new()
	state = Game2048State.create(_seed, config)
	_phase = Phase.PLAYING
	_input_gate_open = true
	_buffered_dir = -1
	_win_shown = false
	_2048_sfx_played = false
	_last_reported_score = -1
	_last_snapshot = {}
	pause_overlay.visible = false
	game_over_overlay.visible = false
	win_overlay.visible = false
	# Reset all existing tiles into the pool.
	for id in _tile_nodes.keys():
		var t: Node2D = _tile_nodes[id]
		t.visible = false
		_tile_pool.append(t)
	_tile_nodes.clear()
	_started = true
	# Configure renderers from config.
	grid_view.configure(config.size, CELL_PX, GAP_PX)
	# Sync tile mirror to current grid (the two starter tiles).
	_sync_tiles_from_state(true)
	# Load best from Settings (0 if absent), push to HUD.
	_best_score = _load_best()
	hud.update_best(_best_score)
	hud.set_undo_enabled(false)
	_emit_score_if_changed()


func pause() -> void:
	if _phase == Phase.PLAYING or _phase == Phase.WON_CONTINUING:
		# Pause overlay overlaps with input gating: while paused, no plans
		# are computed. _phase doesn't change to PAUSED-only because we want
		# resume to drop us back into the same phase we were in.
		pause_overlay.visible = true


func resume() -> void:
	if pause_overlay.visible:
		pause_overlay.visible = false


func teardown() -> void:
	if InputManager.action_pressed.is_connected(_on_action_pressed):
		InputManager.action_pressed.disconnect(_on_action_pressed)
	state = null
	config = null
	_started = false


# --- Loop ---


func _process(_delta: float) -> void:
	if not _started or state == null:
		return
	if _input_gate_open:
		# Replay any buffered direction now that the gate is open.
		if _buffered_dir >= 0:
			var d: int = _buffered_dir
			_buffered_dir = -1
			_apply_direction(d)
		return
	# Gate closed: check whether all tiles have stopped animating.
	if not _any_tile_animating():
		_finish_animation_round()


func _any_tile_animating() -> bool:
	for id in _tile_nodes.keys():
		var t: Node2D = _tile_nodes[id]
		if t.is_animating():
			return true
	return false


# --- Input ---


func _on_action_pressed(action: StringName) -> void:
	if action == &"pause":
		_toggle_pause()
		return
	if action == &"undo":
		_on_undo_invoked()
		return
	if pause_overlay.visible:
		return
	if _phase == Phase.GAME_OVER:
		return
	# Win overlay handles its own input until dismissed.
	if win_overlay.visible:
		return
	var dir: int = -1
	match action:
		&"move_up":    dir = Game2048State.Dir.UP
		&"move_down":  dir = Game2048State.Dir.DOWN
		&"move_left":  dir = Game2048State.Dir.LEFT
		&"move_right": dir = Game2048State.Dir.RIGHT
		_:             return
	if _input_gate_open:
		_apply_direction(dir)
	else:
		# Buffer-1: latest press wins, no queue depth.
		_buffered_dir = dir


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			if _touch_index == -1:
				_touch_index = t.index
				_touch_start = t.position
		else:
			if t.index == _touch_index:
				_resolve_swipe(t.position - _touch_start)
				_touch_index = -1


func _resolve_swipe(delta: Vector2) -> void:
	if pause_overlay.visible or _phase == Phase.GAME_OVER or win_overlay.visible:
		return
	var ax: float = absf(delta.x)
	var ay: float = absf(delta.y)
	if maxf(ax, ay) < SWIPE_MIN_PX:
		return
	var dir: int
	if ax >= ay:
		dir = Game2048State.Dir.RIGHT if delta.x > 0 else Game2048State.Dir.LEFT
	else:
		dir = Game2048State.Dir.DOWN if delta.y > 0 else Game2048State.Dir.UP
	if _input_gate_open:
		_apply_direction(dir)
	else:
		_buffered_dir = dir


# --- Plan-driven move ---


func _apply_direction(dir: int) -> void:
	if state == null:
		return
	var p: Planner.MovePlan = state.plan(dir)
	if p == null or p.is_empty():
		# No-op move: gate stays open, no animation, no spawn.
		return
	# Capture pre-commit snapshot for undo BEFORE state mutates.
	_last_snapshot = state.snapshot()
	# Close the gate and seed animations BEFORE commit, so we know which
	# pre-state cells the surviving / dying tiles came from.
	_input_gate_open = false
	# Snapshot the pre-commit grid so we can rebuild missing tiles after
	# replays / state restoration.
	var max_merge_value: int = 0
	for m in p.moves:
		var tm: Planner.TileMove = m
		var tile: TileScript = _ensure_tile_for(tm.id)
		# Survivors (merged_into == -1) keep their displayed value during the
		# slide; we'll bump value + pop on settle for merge survivors.
		tile.cell = tm.from_cell
		tile.snap_to_cell()
		tile.start_slide(tm.to_cell, SLIDE_MS)
		# Diers vanish at end of slide.
		tile.is_dier = (tm.merged_into != -1)
		# Stash the post-slide value on the tile so we can update it at end.
		tile.set_meta(&"post_value", tm.new_value)
		tile.set_meta(&"to_cell", tm.to_cell)
		tile.set_meta(&"is_merge_survivor", tm.merged_into == -1 and _is_merge_survivor(p, tm))
		# Track the largest merge for tier-aware sfx + haptic.
		if tm.merged_into == -1 and _is_merge_survivor(p, tm):
			if tm.new_value > max_merge_value:
				max_merge_value = tm.new_value
	# Commit the move: state mutates, score updates, new tile spawns.
	state.commit(p)
	# SFX: every non-empty plan plays a slide blip; merges escalate with tier.
	_play_slide_sfx()
	if max_merge_value > 0:
		_play_merge_sfx(max_merge_value)
		var tier: Dictionary = Haptics.tier_for(max_merge_value, _HAPTIC_TIERS)
		Haptics.pulse(float(tier["intensity"]), int(tier["duration_ms"]))
	# Sync new spawn (id present in state but not in our mirror) with fade-in.
	_sync_tiles_from_state(false)
	_emit_score_if_changed()
	# Update best on every score change.
	_update_best()
	# A successful, non-empty commit refills the undo charge.
	hud.set_undo_enabled(not _last_snapshot.is_empty())


# A "merge survivor" is a TileMove where the planner recorded another
# TileMove ending at the same to_cell with merged_into == this tile's id.
static func _is_merge_survivor(p: Planner.MovePlan, tm: Planner.TileMove) -> bool:
	for m in p.moves:
		var other: Planner.TileMove = m
		if other.merged_into == tm.id:
			return true
	return false


func _finish_animation_round() -> void:
	# Apply post-slide value updates, hide diers, fire pops on merge survivors.
	for id in _tile_nodes.keys():
		var tile: TileScript = _tile_nodes[id]
		if tile.has_meta(&"post_value"):
			tile.value = int(tile.get_meta(&"post_value"))
			tile.cell = tile.get_meta(&"to_cell")
			tile.snap_to_cell()
			if bool(tile.get_meta(&"is_merge_survivor", false)):
				tile.start_pop()
			tile.remove_meta(&"post_value")
			tile.remove_meta(&"to_cell")
			tile.remove_meta(&"is_merge_survivor")
	# Reap diers — they were already hidden by their slide handler.
	var dead_ids: Array = []
	for id in _tile_nodes.keys():
		var tile: TileScript = _tile_nodes[id]
		if not tile.visible:
			dead_ids.append(id)
	for id in dead_ids:
		var tile: TileScript = _tile_nodes[id]
		_tile_nodes.erase(id)
		_tile_pool.append(tile)
	# Win check (acceptance #5: fire once).
	if state != null and state.is_won() and not _win_shown:
		_win_shown = true
		_phase = Phase.WON_CONTINUING
		if not _2048_sfx_played:
			_2048_sfx_played = true
			if _sfx_2048 != null:
				_sfx_2048.play()
		win_overlay.show_with(int(state.snapshot().get("score", 0)))
		# Don't reopen the gate while the win overlay is visible; it gets
		# reopened in _on_continue_pressed.
		hud.set_undo_enabled(false)
		return
	# Game-over check (acceptance #6).
	if state != null and state.is_lost():
		_phase = Phase.GAME_OVER
		if _sfx_over != null:
			_sfx_over.play()
		game_over_overlay.show_with(int(state.snapshot().get("score", 0)))
		hud.set_undo_enabled(false)
		return
	_input_gate_open = true
	hud.set_undo_enabled(_can_undo())


# --- Tile pool ---


func _ensure_tile_for(id: int) -> TileScript:
	if _tile_nodes.has(id):
		return _tile_nodes[id]
	var t: TileScript = _take_tile_from_pool()
	t.tile_id = id
	t.visible = true
	t.modulate.a = 1.0
	t.scale = Vector2.ONE
	_tile_nodes[id] = t
	return t


func _take_tile_from_pool() -> TileScript:
	if not _tile_pool.is_empty():
		return _tile_pool.pop_back()
	var t: TileScript = TileScript.new()
	t.configure(CELL_PX, Vector2.ZERO, GAP_PX)
	tiles_root.add_child(t)
	return t


# Build / refresh `_tile_nodes` from `state._grid`. On `initial == true`
# (after start()), every tile snaps in with no animation. Otherwise, only
# new ids (not currently mirrored) are spawned with fade-in.
func _sync_tiles_from_state(initial: bool) -> void:
	if state == null:
		return
	var snap: Dictionary = state.snapshot()
	var grid: Array = snap.get("grid", [])
	for r in grid.size():
		var row: Array = grid[r]
		for c in row.size():
			var cell: Dictionary = row[c]
			var id: int = int(cell.get("id", 0))
			if id == 0:
				continue
			var v: int = int(cell.get("value", 0))
			if not _tile_nodes.has(id):
				var t: TileScript = _ensure_tile_for(id)
				t.value = v
				t.cell = Vector2i(c, r)
				t.snap_to_cell()
				if not initial:
					t.start_fade_in()
			else:
				var tile: TileScript = _tile_nodes[id]
				# Update value/cell only if not currently in a slide (in-flight
				# slides own these; we set them at settle time).
				if not tile.is_animating() and not tile.has_meta(&"post_value"):
					tile.value = v
					tile.cell = Vector2i(c, r)
					tile.snap_to_cell()


func _emit_score_if_changed() -> void:
	if state == null:
		return
	var snap: Dictionary = state.snapshot()
	hud.update_from_snapshot(snap)
	var s: int = int(snap.get("score", 0))
	if s != _last_reported_score:
		_last_reported_score = s
		score_reported.emit(s)


# --- Pause / overlays ---


func _toggle_pause() -> void:
	if _phase == Phase.GAME_OVER:
		return
	if pause_overlay.visible:
		resume()
	else:
		pause()


func _on_restart_pressed() -> void:
	game_over_overlay.visible = false
	# Fresh seed for replay; tests override start() afterwards if needed.
	start(_seed + 1)


func _on_continue_pressed() -> void:
	win_overlay.visible = false
	# Game continues with current state and score. Acceptance #5: subsequent
	# moves don't re-show this overlay.
	_phase = Phase.WON_CONTINUING
	_input_gate_open = true
	hud.set_undo_enabled(_can_undo())


func _on_menu_pressed() -> void:
	exit_requested.emit()


# --- Polish helpers (issue #21) ---


func _can_undo() -> bool:
	if _last_snapshot.is_empty():
		return false
	if not _input_gate_open:
		return false
	if pause_overlay.visible or win_overlay.visible or game_over_overlay.visible:
		return false
	return true


## Restore _last_snapshot to state, rebuild tile mirror, clear undo charge.
## Bound to both `undo` action and the HUD button.
func _on_undo_invoked() -> void:
	if not _can_undo():
		return
	state = Game2048State.from_snapshot(_last_snapshot)
	_last_snapshot = {}
	# Wipe tile mirror — `_sync_tiles_from_state(true)` snaps every restored
	# tile to its restored cell with no animation, which is exactly what we
	# want after an undo (no slide/pop fanfare).
	for id in _tile_nodes.keys():
		var t: Node2D = _tile_nodes[id]
		t.visible = false
		_tile_pool.append(t)
	_tile_nodes.clear()
	_sync_tiles_from_state(true)
	_emit_score_if_changed()
	hud.set_undo_enabled(false)


func _play_slide_sfx() -> void:
	if _sfx_slide == null:
		return
	_sfx_slide.play()


func _play_merge_sfx(merged_value: int) -> void:
	if _sfx_merge == null:
		return
	# Merged values are powers of 2 starting at 4. Map exponent → frequency:
	# higher tiles ring at lower pitch (heavier feel).
	var exp: float = clamp(log(float(merged_value)) / log(2.0), 2.0, 14.0)
	var freq: float = 880.0 - 50.0 * (exp - 2.0)
	_sfx_merge.stream = SfxTones.tone_chord([freq, freq * 1.5], 0.10, 0.5)
	_sfx_merge.play()


func _load_best() -> int:
	if not _has_settings():
		return 0
	return int(Settings.get_value(BEST_KEY, 0))


func _save_best(value: int) -> void:
	if not _has_settings():
		return
	Settings.set_value(BEST_KEY, value)


## Push the current score to `g2048.best` if higher, and refresh the HUD label.
func _update_best() -> void:
	if state == null:
		return
	var s: int = int(state.snapshot().get("score", 0))
	if s > _best_score:
		_best_score = s
		_save_best(_best_score)
		hud.update_best(_best_score)
