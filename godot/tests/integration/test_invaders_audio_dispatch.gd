extends GutTest
## Audio-dispatch tests for invaders polish (#29).
##
## The dispatcher is a pure-ish helper called once per tick that diffs two
## snapshots and routes events to a recorder via _audio.play / _audio.stop.
## We bypass _process and tick() entirely — just construct snapshot pairs and
## call _audio_dispatch directly, asserting recorder calls match expectations.
##
## Covers acceptance criteria #2 (4-tone cycle), #3 (fire haptic on accepted
## shot), #5 (UFO loop start/stop + UFO-kill vs UFO-exit distinction), and #6
## (no step-tone during interlude).

var scene: Control
var rec: _Recorder


# --- Recorder: minimal duck-typed audio sink ---

class _Recorder:
	extends RefCounted
	var calls: Array = []   # Array of [op: "play"|"stop", key: StringName]
	func play(key: StringName) -> void:
		calls.append(["play", key])
	func stop(key: StringName) -> void:
		calls.append(["stop", key])
	func keys_played(prefix: String = "") -> Array:
		var out: Array = []
		for c in calls:
			if c[0] == "play" and (prefix == "" or String(c[1]).begins_with(prefix)):
				out.append(c[1])
		return out


func before_each() -> void:
	var packed: PackedScene = load("res://scenes/invaders/invaders.tscn")
	scene = packed.instantiate()
	add_child(scene)
	await get_tree().process_frame
	# Inject recorder BEFORE start() — start() resets _step_index to 0.
	rec = _Recorder.new()
	scene._inject_audio(rec)
	scene.start(0)
	await get_tree().process_frame
	rec.calls.clear()  # discard anything from the initial _redraw_all


func after_each() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
	await get_tree().process_frame


# --- Snapshot fixture helpers ---

static func _snap(formation_dx: float = 0.0, lives: int = 3, score: int = 0,
		wave: int = 1, ufo_present: bool = false, bullet_alive: bool = false,
		enemies_alive_count: int = -1) -> Dictionary:
	var enemies: PackedByteArray = PackedByteArray()
	# 5 cells, all alive by default; tests that need kills override count.
	enemies.resize(5)
	var n: int = 5 if enemies_alive_count == -1 else enemies_alive_count
	for i in 5:
		enemies[i] = 1 if i < n else 0
	var s: Dictionary = {
		"formation": {"ox": formation_dx, "oy": 0.0, "dir": 1, "last_step_ms": 0},
		"player_bullet": {"alive": bullet_alive},
		"enemies": enemies,
		"lives": lives,
		"score": score,
		"wave": wave,
		"ufo": {"x": 100.0, "y": 20.0} if ufo_present else null,
	}
	return s


# --- Acceptance #2: four-tone cycle ---

func test_eight_consecutive_steps_cycle_through_four_tones() -> void:
	var prev: Dictionary = _snap(0.0)
	var played: Array = []
	for i in 8:
		# Bump ox so the dispatcher detects a "moved" formation.
		var curr: Dictionary = _snap(float(i + 1) * 4.0)
		scene._audio_dispatch(prev, curr, false)
		prev = curr
	played = rec.keys_played("step_")
	assert_eq(played.size(), 8, "eight step events")
	var expected: Array = [
		&"step_1", &"step_2", &"step_3", &"step_4",
		&"step_1", &"step_2", &"step_3", &"step_4",
	]
	for i in 8:
		assert_eq(played[i], expected[i],
			"step %d cycles to %s" % [i, String(expected[i])])


# --- Acceptance #6: no step tone during interlude ---

func test_no_step_tone_dispatched_during_interlude() -> void:
	var prev: Dictionary = _snap(0.0)
	# Same kind of formation motion, but flagged as in-interlude.
	for i in 60:   # 60 frames ~ 1 second of "interlude"
		var curr: Dictionary = _snap(float(i + 1) * 4.0)
		scene._audio_dispatch(prev, curr, true)
		prev = curr
	assert_eq(rec.keys_played("step_").size(), 0,
		"no step_* events while in interlude")


# --- Acceptance #3: fire SFX (and haptic) only on accepted shot ---

func test_fire_sfx_only_on_player_bullet_zero_to_one_edge() -> void:
	var prev: Dictionary = _snap(0.0, 3, 0, 1, false, false)
	var curr: Dictionary = _snap(0.0, 3, 0, 1, false, true)
	scene._audio_dispatch(prev, curr, false)
	assert_eq(rec.keys_played().has(&"fire"), true, "fire SFX on 0→1 bullet edge")

	rec.calls.clear()
	# Already-alive → still alive: no new fire.
	scene._audio_dispatch(curr, curr, false)
	assert_eq(rec.keys_played().has(&"fire"), false,
		"no fire SFX while bullet stays alive")

	rec.calls.clear()
	# Bullet vanishes (offscreen / hit) → no fire SFX (only 0→1 fires).
	var gone: Dictionary = _snap(0.0, 3, 0, 1, false, false)
	scene._audio_dispatch(curr, gone, false)
	assert_eq(rec.keys_played().has(&"fire"), false, "no fire SFX on 1→0 edge")


# --- Acceptance #5: UFO loop / kill vs exit ---

func test_ufo_loop_starts_when_ufo_appears() -> void:
	var prev: Dictionary = _snap(0.0, 3, 0, 1, false)
	var curr: Dictionary = _snap(0.0, 3, 0, 1, true)
	scene._audio_dispatch(prev, curr, false)
	var plays: Array = rec.keys_played()
	assert_eq(plays.has(&"ufo_loop"), true, "ufo_loop plays on null→present")


func test_ufo_kill_jingle_only_when_score_increased() -> void:
	# UFO killed: present→null AND score went up.
	var prev_ufo: Dictionary = _snap(0.0, 3, 0, 1, true)
	var killed: Dictionary = _snap(0.0, 3, 100, 1, false)
	scene._audio_dispatch(prev_ufo, killed, false)
	var stops: Array = []
	var plays: Array = []
	for c in rec.calls:
		if c[0] == "stop": stops.append(c[1])
		else: plays.append(c[1])
	assert_eq(stops.has(&"ufo_loop"), true, "ufo_loop stops")
	assert_eq(plays.has(&"ufo_kill"), true, "ufo_kill plays on killed (score went up)")

	# UFO exited offscreen: present→null AND score unchanged → no jingle.
	rec.calls.clear()
	var exited: Dictionary = _snap(0.0, 3, 0, 1, false)
	scene._audio_dispatch(prev_ufo, exited, false)
	stops = []
	plays = []
	for c in rec.calls:
		if c[0] == "stop": stops.append(c[1])
		else: plays.append(c[1])
	assert_eq(stops.has(&"ufo_loop"), true, "ufo_loop still stops on exit")
	assert_eq(plays.has(&"ufo_kill"), false,
		"no ufo_kill jingle when score unchanged (UFO flew off)")


# --- Auxiliary: enemy explosions, lives, wave clear ---

func test_enemy_explosion_per_lost_cell() -> void:
	var prev: Dictionary = _snap(0.0, 3, 0, 1, false, false, 5)
	var curr: Dictionary = _snap(0.0, 3, 30, 1, false, false, 3)   # 2 enemies died
	scene._audio_dispatch(prev, curr, false)
	var explode_count: int = 0
	for c in rec.calls:
		if c[0] == "play" and c[1] == &"explode_enemy":
			explode_count += 1
	assert_eq(explode_count, 2, "one explode_enemy per lost cell")


func test_player_explosion_on_lives_decrement() -> void:
	var prev: Dictionary = _snap(0.0, 3)
	var curr: Dictionary = _snap(0.0, 2)
	scene._audio_dispatch(prev, curr, false)
	assert_eq(rec.keys_played().has(&"explode_player"), true,
		"explode_player on lives drop")


func test_wave_clear_on_wave_increment() -> void:
	var prev: Dictionary = _snap(0.0, 3, 100, 1)
	var curr: Dictionary = _snap(0.0, 3, 100, 2)
	scene._audio_dispatch(prev, curr, false)
	assert_eq(rec.keys_played().has(&"wave_clear"), true,
		"wave_clear plays on wave increment")
