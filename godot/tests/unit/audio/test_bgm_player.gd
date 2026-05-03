extends GutTest
## Unit tests for `BgmPlayer` autoload — registration / pause / has_track.
##
## We do not test playback timing here (would require ProcessFrame waits and a
## real audio backend); fade behavior is exercised manually.

const BgmPlayer := preload("res://globals/bgm_player.gd")

var bgm: AudioStreamPlayer


func before_each() -> void:
	bgm = BgmPlayer.new()
	add_child(bgm)


func after_each() -> void:
	if is_instance_valid(bgm):
		bgm.queue_free()


func test_register_missing_returns_false() -> void:
	assert_false(bgm.register_track(&"tetris", &"theme", "res://assets/audio/tetris/missing_theme.mp3"))
	assert_false(bgm.has_track(&"tetris", &"theme"))


func test_namespaces_isolated() -> void:
	# Use a real file so registration succeeds.
	var path: String = "res://globals/input_manager.gd"
	bgm.register_track(&"a", &"theme", path)
	assert_true(bgm.has_track(&"a", &"theme"))
	assert_false(bgm.has_track(&"b", &"theme"))
	assert_false(bgm.has_track(&"a", &"other"))


func test_play_unregistered_is_silent_noop() -> void:
	# Must not crash, must not change state.
	bgm.play_track(&"tetris", &"never_registered")
	assert_false(bgm.playing)


func test_pause_resume_does_not_crash_when_not_playing() -> void:
	# pause() / resume() on idle player are no-ops, exercised so they don't
	# regress to crashes if `stream_paused` wiring changes.
	bgm.pause()
	bgm.resume()
	assert_false(bgm.playing)
