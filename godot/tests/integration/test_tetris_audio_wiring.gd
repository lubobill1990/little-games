extends GutTest
## Integration test for tetris audio wiring. Replaces the SfxLibrary/BgmPlayer
## autoloads via `tetris.gd._inject_audio()` with a Recorder that captures
## (ns, event) tuples, then exercises selected gameplay actions and asserts
## the recorded sequence.
##
## We don't drive a long deterministic session here — the existing
## tests/integration/test_tetris_scene.gd covers gameplay; this one focuses
## on event ordering and rate-limiting.

const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")
const TetrisGameState := preload("res://scripts/tetris/core/game_state.gd")

# --- Recorder that satisfies both _sfx and _bgm contracts. ---
class Recorder extends Node:
	var events: Array = []        # Array of [ns, event]
	var bgm_calls: Array = []     # play_track / stop_track / pause / resume

	func register_many(_ns: StringName, _mapping: Dictionary) -> void:
		pass
	func register_track(_ns: StringName, _name: StringName, _path: String) -> bool:
		return true
	func play(ns: StringName, event: StringName, _volume_db: float = 0.0) -> void:
		events.append([String(ns), String(event)])
	func play_track(_ns: StringName, _name: StringName, _fade_in: float = 0.5) -> void:
		bgm_calls.append("play_track")
	func stop_track(_fade_out: float = 0.5) -> void:
		bgm_calls.append("stop_track")
	func pause() -> void:
		bgm_calls.append("pause")
	func resume() -> void:
		bgm_calls.append("resume")

	func event_names() -> Array:
		var out: Array = []
		for e in events:
			out.append(e[1])
		return out

	func count(event: String) -> int:
		var n: int = 0
		for e in events:
			if e[1] == event:
				n += 1
		return n


const SEED: int = 12345

var scene: Control
var rec: Recorder


func before_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	await get_tree().process_frame
	rec = Recorder.new()
	add_child(rec)
	var packed: PackedScene = load("res://scenes/tetris/tetris.tscn")
	scene = packed.instantiate()
	add_child(scene)
	await get_tree().process_frame
	# Replace audio singletons before start() so the BGM play_track call lands
	# on the recorder rather than the live autoloads.
	scene._inject_audio(rec, rec)
	scene.start(1)
	# Swap to a deterministic seed for predictable piece sequence (mirrors
	# test_tetris_scene.gd).
	scene.state.piece_locked.disconnect(scene._on_piece_locked)
	scene.state.game_over.disconnect(scene._on_game_over)
	scene.state = TetrisGameState.create(SEED)
	scene.state.piece_locked.connect(scene._on_piece_locked)
	scene.state.game_over.connect(scene._on_game_over)
	scene.playfield.bind(scene.state)
	scene._last_level = scene.state.level()
	scene._update_views()
	await get_tree().process_frame
	# Discard SFX events that fired during start() (none expected, but the
	# guard keeps the test resilient if future changes add boot cues).
	rec.events.clear()


func after_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	if is_instance_valid(scene):
		scene.queue_free()
	if is_instance_valid(rec):
		rec.queue_free()
	await get_tree().process_frame


func _press_release(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame


# --- Tests ---

func test_bgm_play_track_called_on_start() -> void:
	# start() is invoked in before_each(); the recorder's bgm_calls should
	# include exactly one play_track entry by then.
	assert_true(scene._bgm_started, "_bgm_started latched on start()")
	assert_true("play_track" in rec.bgm_calls, "play_track called once on start")


func test_move_left_emits_move_cue() -> void:
	await _press_release(&"move_left")
	assert_true("move" in rec.event_names(), "move SFX fired after move_left")


func test_hard_drop_emits_hard_drop_not_lock() -> void:
	await _press_release(&"hard_drop")
	# hard_drop must precede any piece_locked, and lock SFX must NOT play
	# (suppressed by _hard_drop_this_frame).
	var names: Array = rec.event_names()
	assert_true("hard_drop" in names, "hard_drop SFX fired")
	assert_eq(rec.count("lock"), 0, "lock SFX suppressed when hard_drop produced the lock")


func test_pause_drives_bgm_pause_and_resume() -> void:
	await _press_release(&"pause")
	assert_true("pause" in rec.bgm_calls, "BGM pause called on pause action")
	await _press_release(&"pause")
	assert_true("resume" in rec.bgm_calls, "BGM resume called on second pause action")


func test_input_failed_rate_limited_on_repeat() -> void:
	# Drive move_left repeatedly against the wall via the action_repeated
	# signal directly (DAS would otherwise need 100ms+ per repeat). The first
	# call is is_repeat=false, the next 30 are is_repeat=true; only the first
	# may emit input_failed.
	#
	# We need the piece up against the left wall first. Easiest: hammer
	# move_left until move() returns failure.
	var safety: int = 32
	while safety > 0:
		var r: Dictionary = scene.state.move(-1)
		if not r.success:
			break
		safety -= 1
	assert_lt(safety, 32, "piece reached left wall in test setup")
	rec.events.clear()
	# First (non-repeat) press → 1 input_failed.
	scene._handle_action(&"move_left", false)
	# 30 simulated DAS repeats → must NOT add more input_failed entries.
	for _i in 30:
		scene._handle_action(&"move_left", true)
	assert_eq(rec.count("input_failed"), 1, "input_failed emits once, not per repeat")


func test_game_over_stops_bgm() -> void:
	# Drive game over directly via _enter_game_over so we don't depend on
	# topping out the stack.
	scene._enter_game_over()
	assert_true("stop_track" in rec.bgm_calls, "stop_track called on game over")
	assert_true("game_over" in rec.event_names(), "game_over SFX fired")
