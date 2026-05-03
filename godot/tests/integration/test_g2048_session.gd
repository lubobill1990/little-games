extends GutTest
## Integration: scripted seed + direction log → expected snapshot stream.
## Bypasses scene + input layer; drives Game2048State directly. Verifies
## determinism (acceptance #9).

const Game2048Config := preload("res://scripts/g2048/core/g2048_config.gd")
const Game2048State := preload("res://scripts/g2048/core/g2048_state.gd")

const SEED: int = 4242


func _make_state() -> Game2048State:
	var cfg: Game2048Config = Game2048Config.new()
	cfg.size = 4
	cfg.target_value = 2048
	cfg.four_probability = 0.1
	return Game2048State.create(SEED, cfg)


func test_same_seed_same_dirs_same_snapshot_stream() -> void:
	# Two parallel runs with identical inputs must produce byte-identical
	# snapshot streams.
	var a: Game2048State = _make_state()
	var b: Game2048State = _make_state()
	var dirs: Array[int] = [
		Game2048State.Dir.LEFT,
		Game2048State.Dir.UP,
		Game2048State.Dir.RIGHT,
		Game2048State.Dir.DOWN,
		Game2048State.Dir.LEFT,
		Game2048State.Dir.UP,
		Game2048State.Dir.LEFT,
		Game2048State.Dir.RIGHT,
	]
	var snaps_a: Array[Dictionary] = []
	var snaps_b: Array[Dictionary] = []
	for d in dirs:
		a.apply(d)
		b.apply(d)
		snaps_a.append(a.snapshot())
		snaps_b.append(b.snapshot())
	assert_eq(snaps_a, snaps_b, "snapshot streams must match for identical seed+inputs")


func test_no_op_move_does_not_advance_state() -> void:
	# Acceptance #7: a no-op (LEFT on a row already left-packed with no merges)
	# must not change the grid, score, or spawn a new tile.
	var s: Game2048State = _make_state()
	# Force a known board: top row [2,4,8,16], rest empty. Not really legal to
	# do via plan/commit, but `from_snapshot` lets us synthesize.
	var snap: Dictionary = s.snapshot()
	snap["grid"] = [
		[{"id": 1, "value": 2}, {"id": 2, "value": 4}, {"id": 3, "value": 8}, {"id": 4, "value": 16}],
		[{"id": 0, "value": 0}, {"id": 0, "value": 0}, {"id": 0, "value": 0}, {"id": 0, "value": 0}],
		[{"id": 0, "value": 0}, {"id": 0, "value": 0}, {"id": 0, "value": 0}, {"id": 0, "value": 0}],
		[{"id": 0, "value": 0}, {"id": 0, "value": 0}, {"id": 0, "value": 0}, {"id": 0, "value": 0}],
	]
	snap["next_id"] = 5
	snap["score"] = 0
	var s2: Game2048State = Game2048State.from_snapshot(snap)
	var before: Dictionary = s2.snapshot()
	var changed: bool = s2.apply(Game2048State.Dir.LEFT)
	assert_false(changed, "left on packed row is a no-op")
	var after: Dictionary = s2.snapshot()
	assert_eq(after["grid"], before["grid"], "grid unchanged on no-op")
	assert_eq(after["score"], before["score"], "score unchanged on no-op")


func test_session_eventually_terminates_or_progresses() -> void:
	# Run a fixed-seed session and assert the score is monotone non-decreasing,
	# and that within 500 moves the score grew above zero (sanity for a 4×4
	# board with seed 4242 + alternating directions).
	var s: Game2048State = _make_state()
	var dirs: Array[int] = [
		Game2048State.Dir.LEFT, Game2048State.Dir.DOWN,
		Game2048State.Dir.RIGHT, Game2048State.Dir.UP,
	]
	var prev_score: int = 0
	var moves: int = 0
	while moves < 500 and not s.is_lost():
		s.apply(dirs[moves % 4])
		var sc: int = int(s.snapshot()["score"])
		assert_true(sc >= prev_score, "score is monotone non-decreasing")
		prev_score = sc
		moves += 1
	assert_true(prev_score > 0 or s.is_lost(),
		"either score grew or board filled within 500 moves")
