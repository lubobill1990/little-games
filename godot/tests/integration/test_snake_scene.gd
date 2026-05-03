extends GutTest
## Scene-level integration test for Snake. Uses Input.action_press /
## Input.action_release so the InputManager autoload's actual code path runs
## (matching CLAUDE.md §5 test-layering and the pattern in
## tests/integration/test_tetris_scene.gd).
##
## Determinism: the scene's SnakeGameState is replaced with a fresh, seeded
## one in before_each so the snake's body / food positions are reproducible.

const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")
const SnakeConfig := preload("res://scripts/snake/core/snake_config.gd")
const SnakeGameState := preload("res://scripts/snake/core/snake_state.gd")

const SEED: int = 12345

var scene: Control

func before_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	await get_tree().process_frame
	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/snake/snake.tscn")
	scene = packed.instantiate()
	add_child(scene)
	await get_tree().process_frame
	# Force deterministic state.
	scene.start(SEED)
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

func test_move_up_action_buffers_turn() -> void:
	# Snake starts facing RIGHT. move_up should buffer a UP turn.
	await _press_release(&"move_up")
	assert_eq(scene.state._pending_dir, SnakeGameState.Dir.UP, "pending dir buffered to UP")

func test_move_down_action_buffers_turn() -> void:
	# Starts RIGHT; move_down is not opposite, so it buffers.
	await _press_release(&"move_down")
	assert_eq(scene.state._pending_dir, SnakeGameState.Dir.DOWN, "pending dir buffered to DOWN")

func test_180_reverse_is_rejected() -> void:
	# Starts RIGHT; move_left is opposite — core rejects.
	await _press_release(&"move_left")
	assert_eq(scene.state._pending_dir, -1, "180 reverse not buffered")
	assert_eq(scene.state._dir, SnakeGameState.Dir.RIGHT, "still moving right")

func test_pause_action_blocks_state_tick() -> void:
	var snap_before: Dictionary = scene.state.snapshot()
	await _press_release(&"pause")
	assert_true(scene.pause_overlay.visible, "pause overlay visible")
	# Burn a few frames; nothing in state should advance.
	for _i in 5:
		await get_tree().process_frame
	var snap_after: Dictionary = scene.state.snapshot()
	assert_eq(snap_after["snake"], snap_before["snake"], "snake unchanged while paused")
	# Resume.
	await _press_release(&"pause")
	assert_false(scene.pause_overlay.visible, "pause overlay hidden")

func test_game_over_triggers_overlay() -> void:
	# Force game over directly on core; scene picks it up next _process tick.
	scene.state._game_over = true
	for _i in 3:
		await get_tree().process_frame
	assert_true(scene.game_over_overlay.visible, "game over overlay visible")
	assert_true(scene.state.is_game_over(), "state in game-over")

func test_restart_after_game_over_resets_state() -> void:
	scene.state._game_over = true
	for _i in 3:
		await get_tree().process_frame
	# Press ui_accept; overlay listens via InputManager.
	await _press_release(&"ui_accept")
	await get_tree().process_frame
	assert_false(scene.state.is_game_over(), "fresh state not game-over")
	assert_eq(scene.state._score, 0, "score reset")
	assert_false(scene.game_over_overlay.visible, "overlay hidden after restart")

func test_score_reported_signal_fires_on_change() -> void:
	# Start has score 0, _last_reported_score == 0 after _update_views.
	# Bump score artificially and update views; signal should fire once with 1.
	var observed: Array[int] = []
	var cb := func(v: int) -> void: observed.append(v)
	scene.score_reported.connect(cb)
	scene.state._score = 1
	scene._update_views()
	scene.score_reported.disconnect(cb)
	assert_true(observed.has(1), "score_reported emitted with new score")
