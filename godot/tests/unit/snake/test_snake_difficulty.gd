extends GutTest
## Difficulty bucket data + key helpers (#19).

const Difficulty := preload("res://scripts/snake/difficulty.gd")


func test_three_difficulties() -> void:
	var ids: Array = Difficulty.ids()
	assert_eq(ids.size(), 3)
	assert_true(ids.has("easy") and ids.has("normal") and ids.has("hard"))


func test_default_id_is_normal() -> void:
	assert_eq(Difficulty.DEFAULT_ID, "normal")


func test_easy_uses_wrap_normal_and_hard_use_walls() -> void:
	assert_false(bool(Difficulty.by_id("easy")["walls"]))
	assert_true(bool(Difficulty.by_id("normal")["walls"]))
	assert_true(bool(Difficulty.by_id("hard")["walls"]))


func test_step_ms_is_monotonically_decreasing() -> void:
	var e: int = int(Difficulty.by_id("easy")["start_step_ms"])
	var n: int = int(Difficulty.by_id("normal")["start_step_ms"])
	var h: int = int(Difficulty.by_id("hard")["start_step_ms"])
	assert_true(e > n and n > h, "easy(%d) > normal(%d) > hard(%d)" % [e, n, h])


func test_unknown_id_falls_back_to_default() -> void:
	var d: Dictionary = Difficulty.by_id("nope")
	assert_eq(String(d["id"]), Difficulty.DEFAULT_ID)


func test_best_key_is_namespaced_per_difficulty() -> void:
	assert_eq(String(Difficulty.best_key("easy")), "snake.best.easy")
	assert_eq(String(Difficulty.best_key("normal")), "snake.best.normal")
	assert_eq(String(Difficulty.best_key("hard")), "snake.best.hard")


func test_last_key_constant() -> void:
	assert_eq(String(Difficulty.LAST_KEY), "snake.last_difficulty")
