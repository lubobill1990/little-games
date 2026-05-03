extends GutTest
## SnakeRng — determinism + range correctness.

const SnakeRng := preload("res://scripts/snake/core/snake_rng.gd")


func test_same_seed_produces_same_sequence() -> void:
	var a := SnakeRng.create(42)
	var b := SnakeRng.create(42)
	for _i in 100:
		assert_eq(a.randi_below(1000), b.randi_below(1000))


func test_different_seeds_diverge() -> void:
	var a := SnakeRng.create(1)
	var b := SnakeRng.create(2)
	var diffs: int = 0
	for _i in 50:
		if a.randi_below(1_000_000) != b.randi_below(1_000_000):
			diffs += 1
	assert_gt(diffs, 30, "two different seeds should produce mostly different outputs")


func test_randi_below_stays_in_range() -> void:
	var r := SnakeRng.create(7)
	for _i in 200:
		var v: int = r.randi_below(10)
		assert_true(v >= 0 and v < 10, "out of range: %d" % v)
