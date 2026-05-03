extends GutTest
## Scene-level integration test for breakout. Drives the scene via Input
## actions so InputManager's real path runs (matches snake/g2048 patterns).
##
## Determinism: scene.start(SEED) replaces BreakoutGameState with a fresh,
## seeded one in before_each.

const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")
const BreakoutGameState := preload("res://scripts/breakout/core/breakout_state.gd")
const BreakoutLevel := preload("res://scripts/breakout/core/breakout_level.gd")

const SEED: int = 12345

var scene: Control


func before_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	await get_tree().process_frame
	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/breakout/breakout.tscn")
	scene = packed.instantiate()
	add_child(scene)
	await get_tree().process_frame
	scene.start(SEED)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	if is_instance_valid(scene):
		scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _press_release(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame


# --- Tests ---


func test_starts_in_sticky_with_full_lives() -> void:
	# Acceptance #5: sticky on start; HUD shows lives_start.
	var snap: Dictionary = scene.state.snapshot()
	assert_eq(int(snap.get("mode", -1)), BreakoutGameState.Mode.STICKY,
		"breakout starts in sticky mode")
	assert_eq(int(snap.get("lives", 0)), scene.config.lives_start,
		"starts with lives_start lives")
	assert_eq(int(snap.get("score", -1)), 0, "starts with zero score")


func test_hard_drop_action_launches_ball() -> void:
	# Acceptance #5: launch leaves sticky.
	assert_eq(scene.state.mode, BreakoutGameState.Mode.STICKY)
	await _press_release(&"hard_drop")
	# Allow one process tick for state.tick to advance.
	await get_tree().process_frame
	assert_eq(scene.state.mode, BreakoutGameState.Mode.LIVE,
		"hard_drop launches ball into LIVE mode")
	assert_ne(scene.state.ball_vy, 0.0, "ball has non-zero vy after launch")


func test_move_right_drives_paddle_intent() -> void:
	# Acceptance #3: paddle responds within one frame to keypress.
	var initial_x: float = scene.state.paddle_x
	Input.action_press(&"move_right")
	# Two process frames for InputManager → scene → state.tick to apply.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(&"move_right")
	assert_gt(scene.state.paddle_x, initial_x,
		"paddle x increased after holding move_right")


func test_pause_blocks_paddle_motion() -> void:
	# Acceptance: pause stops the sim.
	await _press_release(&"hard_drop")
	await get_tree().process_frame
	await _press_release(&"pause")
	await get_tree().process_frame
	assert_true(scene.pause_overlay.visible, "pause overlay visible")
	var x_at_pause: float = scene.state.paddle_x
	var ball_x_at_pause: float = scene.state.ball_x
	# Hold move_right for several frames; nothing should happen.
	Input.action_press(&"move_right")
	for _i in 5:
		await get_tree().process_frame
	Input.action_release(&"move_right")
	assert_almost_eq(scene.state.paddle_x, x_at_pause, 0.01,
		"paddle did not move while paused")
	assert_almost_eq(scene.state.ball_x, ball_x_at_pause, 0.01,
		"ball did not move while paused")
	# Resume.
	await _press_release(&"pause")
	assert_false(scene.pause_overlay.visible, "pause overlay hidden after resume")


func test_game_over_overlay_path() -> void:
	# Force LOST mode and let the scene react.
	scene.state.mode = BreakoutGameState.Mode.LOST
	scene.state.lives = 0
	for _i in 5:
		await get_tree().process_frame
	assert_true(scene.game_over_overlay.visible,
		"game-over overlay visible once state is LOST")


func test_win_overlay_path() -> void:
	# Force WON mode and let the scene react.
	scene.state.mode = BreakoutGameState.Mode.WON
	for _i in 5:
		await get_tree().process_frame
	assert_true(scene.win_overlay.visible,
		"win overlay visible once state is WON")


func test_restart_after_game_over_resets_state() -> void:
	# Force a game over.
	scene.state.mode = BreakoutGameState.Mode.LOST
	scene.state.lives = 0
	for _i in 5:
		await get_tree().process_frame
	assert_true(scene.game_over_overlay.visible)
	# Restart via scene method (UI-equivalent).
	scene._on_restart_pressed()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(scene.state.mode, BreakoutGameState.Mode.STICKY,
		"restart returns to STICKY mode")
	assert_eq(scene.state.lives, scene.config.lives_start,
		"restart restores lives_start lives")
	assert_false(scene.game_over_overlay.visible,
		"game-over overlay hidden after restart")
