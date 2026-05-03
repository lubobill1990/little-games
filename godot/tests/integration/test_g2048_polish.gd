extends GutTest
## 2048 scene polish tests (#21): undo round-trip, undo gating, best-score
## persistence across scene reloads.

const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")
const Game2048State := preload("res://scripts/g2048/core/g2048_state.gd")

const SEED: int = 4242

var scene: Control


func _settings() -> Node:
	return Engine.get_main_loop().root.get_node("Settings")


func before_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	_settings().reset_defaults()
	# Wipe the persisted best-score key so each test starts from zero.
	_settings().set_value(&"g2048.best", 0)
	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/g2048/g2048.tscn")
	scene = packed.instantiate()
	add_child(scene)
	await get_tree().process_frame
	scene.start(SEED)
	await get_tree().process_frame


func after_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	if is_instance_valid(scene):
		scene.queue_free()
	_settings().reset_defaults()
	await get_tree().process_frame


func _drain(max_frames: int = 40) -> void:
	for _i in max_frames:
		if scene._input_gate_open:
			return
		await get_tree().process_frame


# Drive a sequence of move directions until at least one of them produces a
# non-empty plan (i.e. score-changing). Returns true if a real move happened.
func _make_a_real_move() -> bool:
	for action in [&"move_left", &"move_up", &"move_right", &"move_down"]:
		var before: Dictionary = scene.state.snapshot()
		Input.action_press(action)
		await get_tree().process_frame
		await get_tree().process_frame
		Input.action_release(action)
		await get_tree().process_frame
		await _drain()
		var after: Dictionary = scene.state.snapshot()
		if before["grid"] != after["grid"]:
			return true
	return false


# --- Acceptance #4 / #5: undo round-trip, gating ---


func test_undo_disabled_before_first_move() -> void:
	assert_false(scene._can_undo(), "undo should not be available before a move")
	# HUD button is disabled by start().
	var btn: Button = scene.hud._undo_button
	assert_true(btn.disabled, "HUD undo button starts disabled")


func test_undo_round_trip_restores_grid_score_and_ids() -> void:
	var before: Dictionary = scene.state.snapshot()
	var moved: bool = await _make_a_real_move()
	assert_true(moved, "test setup expected at least one of LRUD to move")
	var mid: Dictionary = scene.state.snapshot()
	assert_ne(before["grid"], mid["grid"], "grid changed after move")
	assert_true(scene._can_undo())
	scene._on_undo_invoked()
	await get_tree().process_frame
	var after: Dictionary = scene.state.snapshot()
	# Acceptance #4: grid + score + ids exactly match the pre-move snapshot.
	assert_eq(after["grid"], before["grid"], "undo restores grid + ids")
	assert_eq(after["score"], before["score"], "undo restores score")
	assert_false(scene._can_undo(), "undo charge consumed after use")


func test_undo_charge_refills_after_next_real_move() -> void:
	assert_true(await _make_a_real_move())
	scene._on_undo_invoked()
	await get_tree().process_frame
	assert_false(scene._can_undo())
	# Make another real move; charge refills.
	assert_true(await _make_a_real_move())
	assert_true(scene._can_undo(), "undo refills after a non-empty commit")


func test_undo_blocked_during_animation_gate() -> void:
	# Kick off a move, then before draining, _can_undo should be false because
	# _input_gate_open is closed during the slide.
	for action in [&"move_left", &"move_up", &"move_right", &"move_down"]:
		Input.action_press(action)
		await get_tree().process_frame
		await get_tree().process_frame
		Input.action_release(action)
		await get_tree().process_frame
		# Loop until a real move closes the gate.
		if not scene._input_gate_open:
			break
	if not scene._input_gate_open:
		assert_false(scene._can_undo(), "no undo during animation")
		await _drain()


# --- Acceptance #3: best score survives restart ---


func test_best_score_persists_across_scene_restart() -> void:
	assert_true(await _make_a_real_move())
	var first_score: int = int(scene.state.snapshot().get("score", 0))
	# Force best to a known value (>= current score) to detach from RNG.
	_settings().set_value(&"g2048.best", max(first_score, 100))
	# Tear down and rebuild the scene.
	scene.queue_free()
	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/g2048/g2048.tscn")
	scene = packed.instantiate()
	add_child(scene)
	await get_tree().process_frame
	scene.start(SEED + 1)
	await get_tree().process_frame
	# Best label should reflect the persisted value, not 0.
	assert_eq(scene._best_score, max(first_score, 100))


func test_best_score_only_grows() -> void:
	_settings().set_value(&"g2048.best", 9999)
	scene.start(SEED)
	await get_tree().process_frame
	# A real move's score will be much smaller than 9999; best must not regress.
	assert_true(await _make_a_real_move())
	assert_eq(scene._best_score, 9999, "best does not decrease")
	assert_eq(int(_settings().get_value(&"g2048.best", 0)), 9999)
