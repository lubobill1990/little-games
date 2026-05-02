extends GutTest
## Bootstrap smoke test — proves CI + GUT are wired up correctly.
##
## Real coverage starts in task #3 (Tetris core). Until then this exists so
## a failed CI run unambiguously means the test pipeline itself is broken.

func test_truth() -> void:
	assert_eq(1 + 1, 2, "arithmetic still works")

func test_godot_runtime() -> void:
	assert_not_null(Engine.get_version_info(), "Godot runtime present")
	assert_true(Engine.get_version_info().major >= 4, "Godot 4+ required")
