extends GutTest
## Scene-level integration test for invaders. Drives the scene via Input
## actions so InputManager's real path runs. Mirrors test_breakout_scene
## structure.
##
## Determinism: scene.start(SEED) replaces InvadersGameState with a fresh,
## seeded one in before_each.

const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")
const InvadersGameState := preload("res://scripts/invaders/core/invaders_state.gd")
const Palette := preload("res://scripts/invaders/invaders_palette.gd")

const SEED: int = 12345

var scene: Control


func before_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	await get_tree().process_frame
	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/invaders/invaders.tscn")
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


func test_starts_with_full_formation_and_lives() -> void:
	var snap: Dictionary = scene.state.snapshot()
	assert_eq(int(snap.get("wave", -1)), 1, "starts at wave 1")
	assert_eq(int(snap.get("lives", -1)), scene.config.lives_start,
		"starts with lives_start lives")
	assert_eq(int(snap.get("score", -1)), 0, "starts with zero score")
	# Every cell alive.
	var alive: PackedByteArray = snap.get("enemies", PackedByteArray())
	assert_eq(alive.size(), scene.config.rows * scene.config.cols,
		"enemies grid sized rows*cols")
	var live_count: int = 0
	for i in range(alive.size()):
		if alive[i] == 1:
			live_count += 1
	assert_eq(live_count, scene.config.rows * scene.config.cols,
		"every enemy alive at start")


func test_move_right_drives_player() -> void:
	# Acceptance #2: player responds within one frame.
	var initial_x: float = scene.state.player_x
	Input.action_press(&"move_right")
	for _i in 4:
		await get_tree().process_frame
	Input.action_release(&"move_right")
	assert_gt(scene.state.player_x, initial_x,
		"player x increased after holding move_right")


func test_fire_action_spawns_player_bullet() -> void:
	# Acceptance #3: fire triggers state.fire(); a second press is a no-op.
	assert_false(scene.state.player_bullet_alive, "no bullet at start")
	await _press_release(&"fire")
	# One process frame for InputManager → scene → state.fire().
	await get_tree().process_frame
	assert_true(scene.state.player_bullet_alive,
		"player bullet spawned after fire press")
	# Fire again — bullet count must not increase (scene-level no-op).
	await _press_release(&"fire")
	await get_tree().process_frame
	# Still exactly one player bullet (it's a single-bullet rule in core).
	assert_true(scene.state.player_bullet_alive)


func test_pause_blocks_player_motion() -> void:
	await _press_release(&"pause")
	assert_true(scene.pause_overlay.visible, "pause overlay visible after pause")
	var x_at_pause: float = scene.state.player_x
	Input.action_press(&"move_right")
	for _i in 5:
		await get_tree().process_frame
	Input.action_release(&"move_right")
	assert_almost_eq(scene.state.player_x, x_at_pause, 0.01,
		"player x did not change while paused")
	# Resume.
	await _press_release(&"pause")
	assert_false(scene.pause_overlay.visible, "pause overlay hidden after resume")


func test_pause_blocks_state_tick() -> void:
	# Acceptance #5 spirit: while overlay is up, state.tick() returns false.
	await _press_release(&"pause")
	var snap_before: Dictionary = scene.state.snapshot()
	for _i in 5:
		await get_tree().process_frame
	var snap_after: Dictionary = scene.state.snapshot()
	# Formation origin must not move while paused.
	assert_eq(
		(snap_before.get("formation", {}) as Dictionary).get("ox", 0.0),
		(snap_after.get("formation", {}) as Dictionary).get("ox", 0.0),
		"formation ox unchanged while paused"
	)


func test_wave_interlude_blocks_ticks() -> void:
	# Acceptance #5: scene must NOT call state.tick() during the 1.2 s
	# interlude. Force a wave change by clearing the formation directly.
	for i in range(scene.state.live_mask.size()):
		scene.state.live_mask[i] = 0
	# Trigger one tick so core advances to the wave change. After this,
	# wave should increment and the scene should latch INTERLUDE phase.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	# The scene-side phase becomes INTERLUDE on the very tick where wave
	# changed. State now has a fresh full formation again.
	assert_eq(scene._phase, scene.Phase.INTERLUDE,
		"scene latches INTERLUDE phase on wave change")
	assert_true(scene.wave_interlude.visible, "wave interlude visible")
	# During the interlude the formation origin must not move.
	var fm0: Dictionary = scene.state.snapshot().get("formation", {})
	var ox0: float = fm0.get("ox", 0.0)
	for _i in 6:
		await get_tree().process_frame
	# Interlude lasts 1.2 s; six frames at ~16 ms is well inside it.
	var fm1: Dictionary = scene.state.snapshot().get("formation", {})
	assert_eq(fm1.get("ox", 0.0), ox0,
		"formation origin frozen during interlude")


func test_formation_march_pose_alternates() -> void:
	# Acceptance #9: per-cell draw mode toggles between two values across
	# two consecutive formation steps.
	var snap0: Dictionary = scene.state.snapshot()
	var ox0: float = (snap0.get("formation", {}) as Dictionary).get("ox", 0.0)
	# Step the formation directly to avoid waiting on cadence.
	scene.state._step_formation()
	scene._update_views()
	var pose1: int = scene.formation_layer.march_pose()
	scene.state._step_formation()
	scene._update_views()
	var pose2: int = scene.formation_layer.march_pose()
	assert_ne(pose1, pose2, "march pose alternates across consecutive steps")


func test_game_over_overlay_when_lives_zero() -> void:
	# Acceptance #7: game over reachable via lives = 0.
	scene.state.lives = 0
	scene.state.player_alive = false
	for _i in 5:
		await get_tree().process_frame
	assert_true(scene.game_over_overlay.visible,
		"game over overlay visible when lives = 0")


func test_restart_after_game_over_resets_to_wave_1() -> void:
	# Acceptance #7: confirm restarts at wave 1 with a fresh seed.
	scene.state.lives = 0
	scene.state.player_alive = false
	for _i in 5:
		await get_tree().process_frame
	assert_true(scene.game_over_overlay.visible)
	scene._on_restart_pressed()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(scene.state.wave, 1, "restart returns to wave 1")
	assert_eq(scene.state.lives, scene.config.lives_start,
		"restart restores full lives")
	assert_false(scene.game_over_overlay.visible,
		"game over overlay hidden after restart")


func test_teardown_releases_signal_connection() -> void:
	# Acceptance #1 spirit: teardown disconnects from InputManager.
	assert_true(InputManager.action_pressed.is_connected(scene._on_action_pressed),
		"connected before teardown")
	scene.teardown()
	assert_false(InputManager.action_pressed.is_connected(scene._on_action_pressed),
		"disconnected after teardown")
