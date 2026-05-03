extends GutTest
## End-to-end integration test: menu → Tetris → 10 hard-drops → assert state.
##
## Exercises the full launch path (MainMenu instances Tetris under GameRoot,
## calls start(seed), Tetris autoloads InputManager, scripted inputs drive the
## game loop, scoring fires). Distinct from test_tetris_scene.gd which jumps
## straight into the Tetris scene; the value here is asserting the menu's
## host-contract path actually works end-to-end.

const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")
const TetrisGameState := preload("res://scripts/tetris/core/game_state.gd")

const SEED: int = 424242
const NUM_DROPS: int = 10

var menu: Control

func before_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/menu/main_menu.tscn")
	menu = packed.instantiate()
	add_child(menu)
	await get_tree().process_frame

func after_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	if is_instance_valid(menu):
		menu.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func test_full_session_menu_to_tetris_drops_pieces() -> void:
	# 1. Pick the Tetris card and fire its game_chosen signal (same path the
	#    Button's pressed handler would take).
	var tetris_card: Button = null
	for card in menu._cards:
		if card.descriptor().id == &"tetris":
			tetris_card = card
			break
	assert_ne(tetris_card, null, "tetris card present in menu")
	tetris_card.emit_signal(&"game_chosen", tetris_card.descriptor())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(menu._menu_root.visible, "menu hidden after launch")
	assert_eq(menu._game_root.get_child_count(), 1, "tetris running under GameRoot")
	var tetris: Node = menu._active_game

	# 2. Replace the auto-spawned state with a deterministic-seeded one so the
	#    piece sequence is reproducible. (Same pattern test_tetris_scene.gd uses.)
	tetris.state.piece_locked.disconnect(tetris._on_piece_locked)
	tetris.state.game_over.disconnect(tetris._on_game_over)
	tetris.state = TetrisGameState.create(SEED)
	tetris.state.piece_locked.connect(tetris._on_piece_locked)
	tetris.state.game_over.connect(tetris._on_game_over)
	tetris.playfield.bind(tetris.state)
	tetris._logical_now_ms = 0
	tetris._update_views()
	await get_tree().process_frame

	# 3. Drive NUM_DROPS hard drops through the real InputManager → Tetris path.
	#    After each drop, wait for the line-clear animation budget (250ms) plus
	#    a margin so the next press can be processed in the PLAYING phase.
	var initial_score: int = tetris.state.score()
	for i in range(NUM_DROPS):
		Input.action_press(&"hard_drop")
		await get_tree().process_frame
		await get_tree().process_frame
		Input.action_release(&"hard_drop")
		# Run frames until either game-over or playing phase resumes.
		var t0: int = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 350:
			await get_tree().process_frame
			if tetris.state.is_game_over():
				break
		if tetris.state.is_game_over():
			break

	# 4. Assert the session actually progressed: score moved AND/OR cells filled.
	#    Hard drops always award >= 0; if the seed produced a game-over before
	#    NUM_DROPS, the test still passes (we exited early).
	var final_score: int = tetris.state.score()
	assert_gte(final_score, initial_score, "score did not regress")
	var cells_filled: int = 0
	for r in range(20, 40):
		for c in range(0, 10):
			if tetris.state.board.get_cell(c, r) != 0:
				cells_filled += 1
	assert_gt(cells_filled, 0, "at least one cell locked on the playfield")
