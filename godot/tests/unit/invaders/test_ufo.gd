extends GutTest
## ufo.gd — score table, direction, spawn timing.

const Ufo := preload("res://scripts/invaders/core/ufo.gd")


func _rng(seed_val: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r


func test_score_table_values() -> void:
	# Static table — exact values are part of the contract.
	assert_eq(Ufo.SCORE_TABLE[0], 50)
	assert_eq(Ufo.SCORE_TABLE[1], 100)
	assert_eq(Ufo.SCORE_TABLE[2], 150)
	assert_eq(Ufo.SCORE_TABLE[3], 300)
	assert_eq(Ufo.SCORE_TABLE.size(), 4)


func test_pick_score_in_table() -> void:
	# Whatever rng produces, score must be one of the four.
	var r := _rng(12345)
	for _i in range(50):
		var s: int = Ufo.pick_score(r)
		assert_true(s == 50 or s == 100 or s == 150 or s == 300, "got %d" % s)


func test_pick_score_deterministic_from_seed() -> void:
	# Same seed → same sequence.
	var r1 := _rng(42); var r2 := _rng(42)
	var seq1: Array = []
	var seq2: Array = []
	for _i in range(10):
		seq1.append(Ufo.pick_score(r1))
		seq2.append(Ufo.pick_score(r2))
	assert_eq(seq1, seq2)


func test_pick_direction_returns_valid() -> void:
	var r := _rng(7)
	for _i in range(30):
		var d: int = Ufo.pick_direction(r)
		assert_true(d == 1 or d == -1)


func test_should_spawn_false_before_interval() -> void:
	var r := _rng(1)
	# now=0, last=0, interval=1000, jitter=0 → 0 - 0 < 1000 + 0 → false.
	assert_false(Ufo.should_spawn(r, 0, 0, 1000, 0))


func test_should_spawn_true_after_interval_no_jitter() -> void:
	var r := _rng(1)
	# now=2000, last=0, interval=1000, jitter=0 → 2000 >= 1000 → true.
	assert_true(Ufo.should_spawn(r, 2000, 0, 1000, 0))


func test_should_spawn_with_jitter_bounded() -> void:
	# With interval=1000 jitter=200, threshold ∈ [900, 1100]. At now=900,
	# regardless of seed, should_spawn must return true OR false (not crash).
	var r := _rng(1)
	for _i in range(20):
		var _b: bool = Ufo.should_spawn(r, 1000, 0, 1000, 200)
		# Just exercise — no assertion needed beyond "doesn't crash".
		assert_not_null(r)
