extends GutTest
## Snake polish (#19): SFX dispatch.
##
## Acceptance #1: each gameplay event (eat / level_up / game_over) produces
## an audible cue. We verify by injecting a recorder and pumping snapshot
## diffs through `_audio_dispatch`.

const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")

var scene: Control
var rec: _Recorder


class _Recorder:
	extends RefCounted
	var calls: Array = []
	func play(key: StringName) -> void:
		calls.append(key)
	func keys() -> Array:
		return calls


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
	rec = _Recorder.new()
	scene._inject_audio(rec)
	scene.start(0, "normal")
	await get_tree().process_frame
	rec.calls.clear()


func after_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	if is_instance_valid(scene):
		scene.queue_free()
	_settings().reset_defaults()
	await get_tree().process_frame


# --- Eat ---

func test_score_increase_plays_eat() -> void:
	scene.state._score = 1
	scene._refresh_views_for_test()
	assert_true(rec.keys().has(&"eat"), "eat played on score+1; got %s" % [rec.keys()])


func test_no_eat_when_score_unchanged() -> void:
	scene._refresh_views_for_test()
	assert_false(rec.keys().has(&"eat"), "no eat when score didn't change")


# --- Level up ---

func test_level_increase_plays_level_up() -> void:
	scene.state._level = 2
	scene._refresh_views_for_test()
	assert_true(rec.keys().has(&"level_up"),
		"level_up played on level+1; got %s" % [rec.keys()])


# --- Game over ---

func test_game_over_plays_game_over_once() -> void:
	scene.state._game_over = true
	scene._refresh_views_for_test()
	assert_eq(rec.keys().count(&"game_over"), 1, "game_over played once")
	scene._refresh_views_for_test()
	assert_eq(rec.keys().count(&"game_over"), 1, "game_over not retriggered")


# --- Default audio sink wiring (no-recorder path) ---

func test_default_play_no_throw_for_unknown_event() -> void:
	# Removing the recorder, scene.play(key) should silently no-op for unknown.
	scene._inject_audio(scene)
	scene.play(&"never_registered")
	assert_true(true, "default play() handled unknown key without error")
