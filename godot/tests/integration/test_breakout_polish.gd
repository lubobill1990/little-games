extends GutTest
## Breakout polish (#23): persistence keys + pack progression.
##
## Tests cover the scene-level wiring; underlying state behaviour is already
## covered by tests/unit/breakout/test_state_*.gd.

const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")
const BreakoutGameState := preload("res://scripts/breakout/core/breakout_state.gd")
const LevelPack := preload("res://scripts/breakout/level_pack.gd")

const SEED: int = 9001

var scene: Control


func _settings() -> Node:
	return Engine.get_main_loop().root.get_node("Settings")


func before_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	_settings().reset_defaults()
	# Wipe any persisted best for this game so each test starts from zero.
	_settings().set_value(&"breakout.best.level_01", 0)
	_settings().set_value(&"breakout.best.level_02", 0)
	_settings().set_value(&"breakout.best.level_03", 0)
	_settings().set_value(&"breakout.best.run", 0)
	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/breakout/breakout.tscn")
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


# --- Level pack ---


func test_pack_has_three_levels_and_paths_load() -> void:
	assert_eq(LevelPack.size(), 3, "pack ships with 3 levels in v1")
	for i in [1, 2, 3]:
		var path: String = LevelPack.path_for(i)
		assert_true(ResourceLoader.exists(path), "level %d resource exists at %s" % [i, path])
		assert_ne(load(path), null, "level %d loads" % i)


func test_pack_keys_are_zero_padded_two_digit() -> void:
	assert_eq(String(LevelPack.key_for(1)), "breakout.best.level_01")
	assert_eq(String(LevelPack.key_for(2)), "breakout.best.level_02")
	assert_eq(String(LevelPack.key_for(3)), "breakout.best.level_03")


# --- Persistence ---


func test_level_clear_persists_per_level_best_and_run() -> void:
	# Force a level-1 win at score=500.
	scene.state.score = 500
	scene.state.mode = BreakoutGameState.Mode.WON
	for _i in 5:
		await get_tree().process_frame
	assert_eq(int(_settings().get_value(&"breakout.best.level_01", 0)), 500,
		"level_01 best updated on clear")
	assert_eq(int(_settings().get_value(&"breakout.best.run", 0)), 500,
		"run best updated on clear")


func test_best_does_not_decrease_on_lower_score_clear() -> void:
	_settings().set_value(&"breakout.best.level_01", 9999)
	_settings().set_value(&"breakout.best.run", 9999)
	scene.state.score = 100
	scene.state.mode = BreakoutGameState.Mode.WON
	for _i in 5:
		await get_tree().process_frame
	assert_eq(int(_settings().get_value(&"breakout.best.level_01", 0)), 9999,
		"per-level best monotonic")
	assert_eq(int(_settings().get_value(&"breakout.best.run", 0)), 9999,
		"run best monotonic")


func test_game_over_persists_run_best_only() -> void:
	_settings().set_value(&"breakout.best.run", 0)
	scene.state.score = 250
	scene.state.lives = 0
	scene.state.mode = BreakoutGameState.Mode.LOST
	for _i in 5:
		await get_tree().process_frame
	assert_eq(int(_settings().get_value(&"breakout.best.run", 0)), 250,
		"run best updated on death")
	# No per-level entry written for a death — game-over isn't a clear.
	assert_eq(int(_settings().get_value(&"breakout.best.level_01", 0)), 0,
		"per-level best NOT updated on death")


# --- Pack progression ---


func test_level_clear_advances_to_next_level_and_carries_score() -> void:
	# Level 1 win at score=300.
	scene.state.score = 300
	scene.state.mode = BreakoutGameState.Mode.WON
	for _i in 5:
		await get_tree().process_frame
	assert_eq(scene._level_index, 1, "still on level 1 until Next is pressed")
	# Press Next.
	scene._on_next_level_pressed()
	await get_tree().process_frame
	assert_eq(scene._level_index, 2, "advanced to level 2")
	assert_eq(scene.state.score, 300, "score carried over")
	assert_eq(scene.state.mode, BreakoutGameState.Mode.STICKY,
		"new level starts in sticky mode")


func test_pack_complete_after_final_level() -> void:
	# Skip directly to level 3 and force a win.
	scene._level_index = LevelPack.size()
	scene._load_level(scene._level_index, 1234, scene.state.lives)
	await get_tree().process_frame
	scene.state.mode = BreakoutGameState.Mode.WON
	for _i in 5:
		await get_tree().process_frame
	assert_true(scene.win_overlay.visible, "win overlay visible after final level")
	assert_eq(scene.win_overlay._mode, scene.win_overlay.Mode.PACK_COMPLETE,
		"win overlay in pack-complete mode")


func test_pack_replay_resets_to_level_one_with_zero_score() -> void:
	scene._level_index = 3
	scene.state.score = 5000
	scene.state.mode = BreakoutGameState.Mode.WON
	for _i in 5:
		await get_tree().process_frame
	# Replay (in pack-complete mode the primary button emits restart).
	scene._on_restart_pressed()
	await get_tree().process_frame
	assert_eq(scene._level_index, 1, "replay returns to level 1")
	assert_eq(scene.state.score, 0, "replay resets score")
