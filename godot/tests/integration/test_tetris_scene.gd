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
	add_child(scene)
	await get_tree().process_frame
	# In production, the scene auto-starts when it's the project's main_scene;
	# under GUT we instantiate it as a child, so call start() explicitly with a
	# throwaway seed, then immediately swap to a deterministic-seeded state.
	scene.start(1)
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

# Regression: line-clear animation must not re-clear rows that core has already
# cleared. Previously the FLASH→SETTLE transition called board.clear_rows again,
# silently deleting the rows that had since shifted into those indices.
func test_line_clear_animation_does_not_double_clear() -> void:
	const Board := preload("res://scripts/tetris/core/board.gd")
	const PieceKind := preload("res://scripts/tetris/core/piece_kind.gd")
	const Piece := preload("res://scripts/tetris/core/piece.gd")
	# Build a board where row 39 is full except cols 1-2 (where the O-piece
	# will land), plus a "survivor" cell at row 37 col 5 that should shift
	# down 1 row when row 39 clears.
	var board = scene.state.board
	board.reset()
	board.set_cell(0, 39, PieceKind.Kind.O)
	for c in range(3, Board.COLS):
		board.set_cell(c, 39, PieceKind.Kind.O)
	board.set_cell(5, 37, PieceKind.Kind.L)
	# Force an O-piece positioned so its bottom row lands in row 39 cols 1-2.
	scene.state.piece = Piece.spawn(PieceKind.Kind.O)
	scene.state.piece.origin = Vector2i(0, 38)  # O cells: (1,38)(2,38)(1,39)(2,39)
	scene.state.piece.rot = 0
	# Lock the piece — core clears row 39 inside _lock_piece, emits piece_locked
	# with cleared_rows=[39], scene transitions to ANIMATING_FLASH.
	scene.state._lock_piece(true)
	await get_tree().process_frame
	assert_eq(scene._phase, scene.Phase.ANIMATING_FLASH, "scene entered flash phase")
	# Drive the scene through FLASH (100 ms) + SETTLE (150 ms). _process reads
	# real wall-clock dt; just await enough frames for total to exceed 250 ms.
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 350:
		await get_tree().process_frame
	# After the clear, the survivor at row 37 col 5 should have shifted down
	# by exactly 1 row (row 38), not been deleted by a double clear.
	assert_eq(board.get_cell(5, 38), PieceKind.Kind.L, "survivor cell preserved post-clear (row 38 col 5)")
	assert_eq(board.get_cell(5, 37), 0, "old position now empty")
