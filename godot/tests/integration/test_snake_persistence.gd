extends GutTest
## Snake polish (#19): persistence + per-difficulty best.
##
## Acceptance #3: best score persists across app restart, scoped per
## difficulty. Acceptance #4: difficulty selection threads through to
## start_step_ms / walls. Acceptance #6: snake.last_difficulty round-trips.

const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")
const Difficulty := preload("res://scripts/snake/difficulty.gd")

const SEED: int = 7777

var scene: Control


func _settings() -> Node:
	return Engine.get_main_loop().root.get_node("Settings")


func before_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	_settings().reset_defaults()
	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/snake/snake.tscn")
	scene = packed.instantiate()
	add_child(scene)
	await get_tree().process_frame
	# Default-start at normal so existing scene-test patterns still work.
	scene.start(SEED, "normal")
	await get_tree().process_frame


func after_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	if is_instance_valid(scene):
		scene.queue_free()
	_settings().reset_defaults()
	await get_tree().process_frame


# --- Acceptance #3: best persists per difficulty ---

func test_persists_new_best_on_game_over() -> void:
	scene.state._score = 42
	scene.state._game_over = true
	scene._enter_game_over()
	assert_eq(int(_settings().get_value(Difficulty.best_key("normal"), -1)), 42,
		"score persisted to snake.best.normal")
	assert_eq(scene._best_score, 42, "in-memory best updated")


func test_does_not_overwrite_higher_existing_best() -> void:
	_settings().set_value(Difficulty.best_key("normal"), 9999)
	scene.start(SEED, "normal")
	await get_tree().process_frame
	scene.state._score = 100
	scene.state._game_over = true
	scene._enter_game_over()
	assert_eq(int(_settings().get_value(Difficulty.best_key("normal"), -1)), 9999,
		"existing higher best is preserved")


func test_best_is_per_difficulty() -> void:
	# Set distinct best scores per bucket; each must round-trip independently.
	_settings().set_value(Difficulty.best_key("easy"), 11)
	_settings().set_value(Difficulty.best_key("normal"), 22)
	_settings().set_value(Difficulty.best_key("hard"), 33)
	scene.start(SEED, "easy")
	await get_tree().process_frame
	assert_eq(scene._best_score, 11, "easy best loaded")
	scene.start(SEED, "hard")
	await get_tree().process_frame
	assert_eq(scene._best_score, 33, "hard best loaded")


# --- Acceptance #4: difficulty threads through to config ---

func test_difficulty_threads_through_to_config() -> void:
	scene.start(SEED, "easy")
	await get_tree().process_frame
	assert_false(scene.config.walls, "easy uses wrap")
	assert_eq(scene.config.start_step_ms, 180, "easy step_ms")
	scene.start(SEED, "hard")
	await get_tree().process_frame
	assert_true(scene.config.walls, "hard uses walls")
	assert_eq(scene.config.start_step_ms, 90, "hard step_ms")


func test_hud_shows_difficulty() -> void:
	scene.start(SEED, "hard")
	await get_tree().process_frame
	assert_eq(scene.hud._difficulty_label.text, "Difficulty: Hard",
		"HUD shows difficulty title")


# --- Acceptance #6: last_difficulty persists ---

func test_picker_choice_persists_last_difficulty() -> void:
	scene._on_difficulty_chosen("hard")
	await get_tree().process_frame
	assert_eq(String(_settings().get_value(Difficulty.LAST_KEY, "")), "hard",
		"last_difficulty saved on pick")


func test_game_over_overlay_shows_best() -> void:
	_settings().set_value(Difficulty.best_key("normal"), 555)
	scene.start(SEED, "normal")
	await get_tree().process_frame
	scene.state._score = 50
	scene.state._game_over = true
	scene._enter_game_over()
	assert_eq(scene.game_over_overlay._best_label.text, "Best: 555",
		"overlay shows persisted best")
