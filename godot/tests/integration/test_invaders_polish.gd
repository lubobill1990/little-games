extends GutTest
## Invaders polish (#29): persistence + best-score wiring.
##
## Acceptance #4: on game-over, the player's score is compared against
## `invaders.best`; if higher, persisted via Settings. The HUD's "Best:" label
## reflects the persisted value at start-of-run, and the game-over overlay
## shows the post-update best.

const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")

const SEED: int = 9001
const BEST_KEY: StringName = &"invaders.best"

var scene: Control


func _settings() -> Node:
	return Engine.get_main_loop().root.get_node("Settings")


func before_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	_settings().reset_defaults()
	_settings().set_value(BEST_KEY, 0)
	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/invaders/invaders.tscn")
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


# --- Persistence ---


func test_initial_best_is_zero_after_reset() -> void:
	assert_eq(scene._best_score, 0, "fresh-install best is zero")


func test_persists_new_best_on_game_over() -> void:
	# Force a game-over with a non-zero score, simulating a real death.
	scene.state.score = 4200
	scene.state.lives = 0
	scene._enter_game_over()
	assert_eq(int(_settings().get_value(BEST_KEY, -1)), 4200,
		"score persisted to invaders.best")
	assert_eq(scene._best_score, 4200,
		"in-memory _best_score updated")


func test_does_not_overwrite_higher_existing_best() -> void:
	_settings().set_value(BEST_KEY, 9999)
	# Re-start so scene reloads best from settings.
	scene.start(SEED)
	await get_tree().process_frame
	scene.state.score = 100
	scene.state.lives = 0
	scene._enter_game_over()
	assert_eq(int(_settings().get_value(BEST_KEY, -1)), 9999,
		"existing higher best is preserved")


func test_game_over_overlay_shows_best() -> void:
	_settings().set_value(BEST_KEY, 7777)
	scene.start(SEED)
	await get_tree().process_frame
	scene.state.score = 50
	scene.state.lives = 0
	scene._enter_game_over()
	# After _enter_game_over, the overlay's _best_label.text should reflect
	# whatever scene._best_score was at that moment (the persisted value).
	var overlay: Node = scene.game_over_overlay
	assert_eq(overlay._best_label.text, "Best: 7777",
		"overlay best label reflects current best")


# --- HUD ---


func test_hud_renders_best_label_from_start() -> void:
	_settings().set_value(BEST_KEY, 1234)
	scene.start(SEED)
	await get_tree().process_frame
	# start() calls _redraw_all → hud.update_from_snapshot(snap, _best_score),
	# so the best label is already populated. No extra tick needed.
	var hud: Node = scene.hud
	assert_eq(hud._best_label.text, "Best: 1234",
		"HUD shows the loaded best score")
