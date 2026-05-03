extends GutTest
## Unit tests for the dive helper (#30). Pure-math + RNG-driven; no scene.

const Dive := preload("res://scripts/invaders/core/dive.gd")


# --- Bezier ---


func test_bezier_endpoints() -> void:
	var p0 := Vector2(0.0, 0.0)
	var p1 := Vector2(50.0, 100.0)
	var p2 := Vector2(100.0, 0.0)
	assert_eq(Dive.bezier_eval(p0, p1, p2, 0.0), p0,
		"t=0 lands on p0")
	assert_eq(Dive.bezier_eval(p0, p1, p2, 1.0), p2,
		"t=1 lands on p2")


func test_bezier_midpoint_matches_analytic() -> void:
	# Acceptance #3: midpoint matches B(0.5) within 1e-5 per axis.
	# B(0.5) = 0.25*p0 + 0.5*p1 + 0.25*p2.
	var p0 := Vector2(10.0, 20.0)
	var p1 := Vector2(50.0, 80.0)
	var p2 := Vector2(90.0, 30.0)
	var got: Vector2 = Dive.bezier_eval(p0, p1, p2, 0.5)
	var expected: Vector2 = 0.25 * p0 + 0.5 * p1 + 0.25 * p2
	assert_almost_eq(got.x, expected.x, 1e-5, "x within 1e-5")
	assert_almost_eq(got.y, expected.y, 1e-5, "y within 1e-5")


func test_bezier_tangent_endpoints_are_chords() -> void:
	var p0 := Vector2(0.0, 0.0)
	var p1 := Vector2(40.0, 60.0)
	var p2 := Vector2(80.0, 0.0)
	# B'(0) = 2*(p1 - p0)
	var t0: Vector2 = Dive.bezier_tangent(p0, p1, p2, 0.0)
	assert_eq(t0, 2.0 * (p1 - p0), "tangent at 0 = 2*(p1-p0)")
	# B'(1) = 2*(p2 - p1)
	var t1: Vector2 = Dive.bezier_tangent(p0, p1, p2, 1.0)
	assert_eq(t1, 2.0 * (p2 - p1), "tangent at 1 = 2*(p2-p1)")


# --- Triggers ---


func test_dive_probability_zero_at_wave_1() -> void:
	assert_eq(Dive.dive_probability(1), 0.0,
		"no dives at wave 1")


func test_dive_probability_ramps_with_wave() -> void:
	assert_almost_eq(Dive.dive_probability(2), 0.15, 1e-6, "wave 2 base = 0.15")
	assert_almost_eq(Dive.dive_probability(8), 0.6, 1e-6, "wave 8 cap = 0.6")
	assert_almost_eq(Dive.dive_probability(20), 0.6, 1e-6, "saturates above wave 8")
	# Monotonic non-decreasing across 2..8.
	var prev: float = 0.0
	for w in range(2, 9):
		var p: float = Dive.dive_probability(w)
		assert_true(p >= prev, "non-decreasing at wave %d (%f >= %f)" % [w, p, prev])
		prev = p


func test_max_active_dives_per_wave() -> void:
	assert_eq(Dive.max_active_dives(1), 0)
	assert_eq(Dive.max_active_dives(2), 1)
	assert_eq(Dive.max_active_dives(3), 1)
	assert_eq(Dive.max_active_dives(4), 2)
	assert_eq(Dive.max_active_dives(8), 4)
	assert_eq(Dive.max_active_dives(99), 4, "saturates at 4")


func test_should_dive_blocked_by_cooldown() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# now=900, last=0, dive_check_ms=1000 → cooldown not elapsed.
	assert_false(Dive.should_dive(rng, 3, 900, 0, 1000, 0),
		"cooldown blocks the attempt")


func test_should_dive_blocked_at_cap() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# Wave 2 cap is 1; active=1 → blocked.
	assert_false(Dive.should_dive(rng, 2, 5000, 0, 1000, 1),
		"at-cap blocks the attempt")


func test_should_dive_zero_at_wave_1() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_false(Dive.should_dive(rng, 1, 9999, 0, 100, 0),
		"wave 1 never dives")


func test_should_dive_passes_when_all_gates_clear() -> void:
	# We craft an RNG whose first randf() is below dive_probability(8)=0.6.
	# Seed 1 happens to produce a small first randf(); but to be robust we
	# loop until we find a seed that does, then use it. (Same trick as
	# tests/unit/invaders/test_ufo.gd uses.)
	var rng := RandomNumberGenerator.new()
	for s in range(1, 200):
		rng.seed = s
		# Don't consume yet — peek.
		var copy := RandomNumberGenerator.new()
		copy.seed = s
		var sample: float = copy.randf()
		if sample < 0.55:
			assert_true(Dive.should_dive(rng, 8, 5000, 0, 1000, 0),
				"seed %d (first randf=%f) passes p=0.6 at wave 8" % [s, sample])
			return
	fail_test("no seed in [1,200) produced a randf() < 0.55 — RNG broken?")


func test_pick_mode_split_is_70_30_under_seed() -> void:
	# 1000 picks under a fixed seed: returning fraction should be near 0.7.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var returning: int = 0
	var n: int = 1000
	for _i in n:
		if Dive.pick_mode(rng) == Dive.MODE_RETURNING:
			returning += 1
	var frac: float = float(returning) / float(n)
	assert_true(frac > 0.65 and frac < 0.75,
		"returning fraction %f near 0.7 over n=%d" % [frac, n])


# --- Path construction ---


func test_returning_path_endpoint_is_slot_exact() -> void:
	# Acceptance #6: returning ends at slot_pos exactly.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var current := Vector2(50.0, 60.0)
	var slot := Vector2(80.0, 40.0)
	var path: Dictionary = Dive.sample_dive_path(rng, Dive.MODE_RETURNING,
			current, slot, 100.0, 224.0, 256.0)
	assert_eq(path["p0"], current, "p0 is current")
	assert_eq(path["p2"], slot, "p2 (returning endpoint) is slot exact")


func test_kamikaze_path_endpoint_below_world() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var current := Vector2(50.0, 60.0)
	var slot := Vector2(80.0, 40.0)
	var path: Dictionary = Dive.sample_dive_path(rng, Dive.MODE_KAMIKAZE,
			current, slot, 120.0, 224.0, 256.0)
	var p2: Vector2 = path["p2"]
	assert_true(p2.y > 256.0, "kamikaze p2 below world bottom (got %f)" % p2.y)
	# x roughly tracks player_x=120.
	assert_almost_eq(p2.x, 120.0, 1e-3, "kamikaze p2.x tracks player_x")


# --- Diver factory ---


func test_make_diver_initial_state() -> void:
	var p0 := Vector2(10, 20)
	var p1 := Vector2(30, 80)
	var p2 := Vector2(50, 200)
	var d: Dictionary = Dive.make_diver(2, 5,
			{"p0": p0, "p1": p1, "p2": p2},
			Dive.MODE_RETURNING, 0.5)
	assert_eq(d["row"], 2)
	assert_eq(d["col"], 5)
	assert_eq(d["mode"], Dive.MODE_RETURNING)
	assert_eq(d["t"], 0.0)
	assert_eq(d["speed"], 0.5)
	assert_eq(d["fire_checkpoints"].size(), Dive.FIRE_CHECKPOINTS.size(),
		"fresh diver has all checkpoints pending")


# --- Tracking bullet velocity ---


func test_tracker_velocity_is_unit_scaled_to_speed() -> void:
	var v: Vector2 = Dive.tracker_velocity(Vector2(10, 10), 70.0, 130.0, 100.0)
	# Vector should have magnitude == bullet_speed (100), normalized direction
	# toward (70, 130) from (10, 10) → dx=60, dy=120, len=√(60²+120²)≈134.16.
	assert_almost_eq(v.length(), 100.0, 1e-3,
		"velocity magnitude == bullet_speed")
	# Direction sanity: dy positive (down), dx positive (rightward).
	assert_true(v.x > 0.0, "vx > 0 toward target right")
	assert_true(v.y > 0.0, "vy > 0 toward target below")


func test_tracker_velocity_handles_target_above() -> void:
	# Edge case: player_y above diver_y. Defensive fallback: straight down.
	var v: Vector2 = Dive.tracker_velocity(Vector2(50, 100), 50.0, 80.0, 100.0)
	assert_eq(v.x, 0.0, "vx zeroed when target above")
	assert_eq(v.y, 100.0, "vy = bullet_speed straight down")
