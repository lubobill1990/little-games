extends GutTest
## Scene-level integration test for the Tetris scene. Drives action signals
## via Input.action_press / Input.action_release so the InputManager autoload's
## actual code path runs (matching CLAUDE.md §5 test layer rule and the pattern
## used by tests/integration/test_input_manager.gd).
##
## The scene's TetrisGameState is replaced with a deterministic-seeded one so
## piece sequence is reproducible.

const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")
const TetrisGameState := preload("res://scripts/tetris/core/game_state.gd")

const SEED: int = 12345

var scene: Control

func before_each() -> void:
	# Drain any held actions from prior tests / autoload startup.
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	await get_tree().process_frame
	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/tetris/tetris.tscn")
	scene = packed.instantiate()
	# Replace the auto-spawned state with a deterministic-seeded one BEFORE
	# adding to tree so _ready uses ours. We can't intercept _ready cleanly,
	# so instead let _ready run with its own state, then swap.
	add_child(scene)
	await get_tree().process_frame
	# Disconnect old signals, replace state with deterministic seed, rewire view.
	scene.state.piece_locked.disconnect(scene._on_piece_locked)
	scene.state.game_over.disconnect(scene._on_game_over)
	scene.state = TetrisGameState.create(SEED)
	scene.state.piece_locked.connect(scene._on_piece_locked)
	scene.state.game_over.connect(scene._on_game_over)
	scene.playfield.bind(scene.state)
	scene._logical_now_ms = 0
	scene._update_views()
	await get_tree().process_frame

func after_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	if is_instance_valid(scene):
		scene.queue_free()
	await get_tree().process_frame

func _press_release(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame

# --- Tests ---

func test_hard_drop_locks_piece_and_scores() -> void:
	var initial_score: int = scene.state.score()
	await _press_release(&"hard_drop")
	# After hard drop a new piece has spawned (or game over). Score is non-negative.
	assert_gte(scene.state.score(), initial_score, "score after hard drop")
	# Some cells in the bottom row must be filled (assuming standard piece doesn't clear).
	var board = scene.state.board
	var any_filled: bool = false
	for c in range(10):
		if board.get_cell(c, 39) != 0:
			any_filled = true
			break
	assert_true(any_filled, "bottom row has at least one locked cell")

func test_move_left_shifts_piece_origin() -> void:
	var origin0: Vector2i = scene.state.current_piece().origin
	await _press_release(&"move_left")
	var origin1: Vector2i = scene.state.current_piece().origin
	assert_eq(origin1.x, origin0.x - 1, "piece moved one column left")

func test_rotate_cw_changes_rotation_state() -> void:
	# Pick a piece that actually rotates (not O). Skip if seed produced O.
	if scene.state.current_piece().kind == 2:  # PieceKind.Kind.O
		pass_test("seed gave O; skipped")
		return
	var rot0: int = scene.state.current_piece().rot
	await _press_release(&"rotate_cw")
	var rot1: int = scene.state.current_piece().rot
	assert_eq(rot1, (rot0 + 1) % 4, "rotation advanced CW")

func test_pause_blocks_state_tick() -> void:
	var snap_before: Dictionary = scene.state.snapshot()
	await _press_release(&"pause")
	assert_true(scene.pause_overlay.visible, "pause overlay visible")
	# Wait several frames; state must be unchanged because tick() is gated.
	for _i in 5:
		await get_tree().process_frame
	var snap_after: Dictionary = scene.state.snapshot()
	assert_eq(snap_after["piece_origin"], snap_before["piece_origin"], "no gravity while paused")
	# Resume.
	await _press_release(&"pause")
	assert_false(scene.pause_overlay.visible, "pause overlay hidden")

func test_game_over_triggers_overlay() -> void:
	# Force game over by directly ending the state.
	scene.state._end_game(scene.state.REASON_TOP_OUT)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(scene.game_over_overlay.visible, "game over overlay visible")
	assert_true(scene.state.is_game_over(), "state in game-over")

func test_restart_after_game_over_resets_state() -> void:
	scene.state._end_game(scene.state.REASON_BLOCK_OUT)
	await get_tree().process_frame
	await get_tree().process_frame
	# Press ui_accept; overlay listens via InputManager.
	await _press_release(&"ui_accept")
	# Allow restart_requested to propagate.
	await get_tree().process_frame
	assert_false(scene.state.is_game_over(), "fresh state not game-over")
	assert_eq(scene.state.score(), 0, "score reset")
	assert_false(scene.game_over_overlay.visible, "overlay hidden after restart")
