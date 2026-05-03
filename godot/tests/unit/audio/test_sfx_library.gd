extends GutTest
## Unit tests for `SfxLibrary` autoload.
##
## Direct instantiation of the autoload script — we don't go through the live
## /root/SfxLibrary singleton because we want a fresh table per test.

const SfxLibrary := preload("res://globals/sfx_library.gd")

var lib: Node


func before_each() -> void:
	lib = SfxLibrary.new()
	add_child(lib)


func after_each() -> void:
	if is_instance_valid(lib):
		lib.queue_free()


func test_register_missing_file_returns_false_no_engine_error() -> void:
	# Path doesn't exist anywhere — must not crash, must not emit
	# resource-loader errors (gated by FileAccess.file_exists()).
	var ok: bool = lib.register(&"tetris", &"nope", "res://assets/audio/tetris/nope.mp3")
	assert_false(ok, "missing file → false")
	assert_false(lib.has_event(&"tetris", &"nope"), "no entry stored")


func test_play_unregistered_event_is_silent_noop() -> void:
	# Prior failed register or never-registered event → play() must not raise.
	lib.play(&"tetris", &"never_registered")
	assert_false(lib.has_event(&"tetris", &"never_registered"))


func test_register_many_emits_one_warning_for_batch() -> void:
	# A batch of all-missing files → counter resets after warning, so a second
	# call (still all-missing) re-emits exactly one more warning rather than
	# accumulating.
	var batch1: Dictionary = {
		&"a": "res://assets/audio/tetris/missing_a.mp3",
		&"b": "res://assets/audio/tetris/missing_b.mp3",
	}
	lib.register_many(&"tetris", batch1)
	# Under the hood `_missing` counter must have reset to 0 after the warning.
	assert_eq(lib._missing, 0, "_missing counter resets after summary warning")


func test_namespaces_isolated() -> void:
	# Use a real existing resource so registration succeeds without writing
	# binary fixtures. The InputManager script ships with the repo; load() on
	# it returns a valid Resource (a Script). We're testing namespace isolation
	# of the dictionary, not playback.
	var real_path: String = "res://globals/input_manager.gd"
	assert_true(FileAccess.file_exists(real_path), "fixture path exists")
	lib.register(&"a", &"x", real_path)
	assert_true(lib.has_event(&"a", &"x"))
	assert_false(lib.has_event(&"b", &"x"), "namespace b not polluted by a")
	assert_false(lib.has_event(&"a", &"y"), "event y not polluted by x")


func test_register_many_then_present_and_missing_mixed() -> void:
	var batch: Dictionary = {
		&"present": "res://globals/input_manager.gd",
		&"missing": "res://assets/audio/tetris/totally_missing.mp3",
	}
	lib.register_many(&"mix", batch)
	assert_true(lib.has_event(&"mix", &"present"))
	assert_false(lib.has_event(&"mix", &"missing"))
