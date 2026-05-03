extends GutTest
## InvadersGameState — lifecycle, public API, snapshot round-trip,
## tunneling cap.

const State := preload("res://scripts/invaders/core/invaders_state.gd")
const Cfg := preload("res://scripts/invaders/core/invaders_config.gd")
const Lvl := preload("res://scripts/invaders/core/invaders_level.gd")


func _cfg() -> Cfg:
	return Cfg.new()


func _lvl() -> Lvl:
	return Lvl.new()


func test_create_default_returns_state() -> void:
	var s = State.create(123, _cfg(), _lvl())
	assert_not_null(s)
	assert_eq(s.lives, 3)
	assert_eq(s.wave, 1)
	assert_eq(s.score, 0)
	assert_eq(s.player_alive, true)
	# Full population.
	assert_eq(s.live_mask.size(), 5 * 11)
	var alive: int = 0
	for i in range(s.live_mask.size()):
		alive += s.live_mask[i]
	assert_eq(alive, 55)


func test_set_player_intent_clamped() -> void:
	var s = State.create(0, _cfg(), _lvl())
	s.set_player_intent(99999.0)
	assert_almost_eq(s.player_intent_vx, 90.0, 1e-6)
	s.set_player_intent(-99999.0)
	assert_almost_eq(s.player_intent_vx, -90.0, 1e-6)
	s.set_player_intent(50.0)
	assert_almost_eq(s.player_intent_vx, 50.0, 1e-6)


func test_fire_single_bullet_invariant() -> void:
	var s = State.create(0, _cfg(), _lvl())
	# First fire succeeds.
	assert_true(s.fire())
	assert_true(s.player_bullet_alive)
	# Second fire while alive → false.
	assert_false(s.fire())
	# Once bullet flies off-screen (manually clear), fire allowed again.
	s.player_bullet_alive = false
	assert_true(s.fire())


func test_fire_when_dead_returns_false() -> void:
	var s = State.create(0, _cfg(), _lvl())
	s.player_alive = false
	assert_false(s.fire())


func test_set_last_tick_resets_clock_without_simulating() -> void:
	var s = State.create(0, _cfg(), _lvl())
	# Run a tick to initialize the clock.
	s.tick(0)
	# Now jump 5 seconds via set_last_tick → no simulation.
	var live_before: int = 0
	for i in range(s.live_mask.size()):
		live_before += s.live_mask[i]
	var ox_before: float = s.formation_ox
	s.set_last_tick(5000)
	# Mask + origin unchanged.
	var live_after: int = 0
	for i in range(s.live_mask.size()):
		live_after += s.live_mask[i]
	assert_eq(live_after, live_before)
	assert_almost_eq(s.formation_ox, ox_before, 1e-6)


func test_tick_returns_bool() -> void:
	var s = State.create(0, _cfg(), _lvl())
	# First tick initializes clock; with no time elapsed across the very
	# first call there shouldn't be motion.
	var changed: bool = s.tick(0)
	# Subsequent tick after some time should change state (player intent
	# is zero, but formation cadence may step).
	assert_typeof(changed, TYPE_BOOL)
	# Run a longer tick — bullets fired, motion applied, etc.
	s.set_player_intent(50.0)
	var c2: bool = s.tick(200)
	assert_true(c2)


func test_is_game_over_initial() -> void:
	var s = State.create(0, _cfg(), _lvl())
	assert_false(s.is_game_over())


func test_current_wave_starts_at_1() -> void:
	var s = State.create(0, _cfg(), _lvl())
	assert_eq(s.current_wave(), 1)


func test_snapshot_has_required_keys() -> void:
	var s = State.create(42, _cfg(), _lvl())
	var snap: Dictionary = s.snapshot()
	assert_eq(snap["version"], 1)
	for key in ["wave", "score", "lives", "formation", "enemies",
			"enemy_kinds", "player", "player_bullet", "enemy_bullets",
			"bunkers", "ufo", "last_ufo_spawn_ms", "divers",
			"rng_master", "rng_bullet", "rng_ufo", "rng_dive"]:
		assert_true(snap.has(key), "snapshot missing key: %s" % key)
	# Reserved fields present and empty/zero-shaped.
	assert_eq(snap["divers"], [])
	assert_eq(snap["ufo"], null)
	assert_eq(snap["rng_master"], 42)


func test_snapshot_round_trip_preserves_state() -> void:
	var s = State.create(7, _cfg(), _lvl())
	# Drive some changes.
	s.set_player_intent(50.0)
	s.tick(0)
	s.tick(500)
	s.fire()
	var snap: Dictionary = s.snapshot()
	var s2 = State.from_snapshot(snap, _cfg(), _lvl())
	var snap2: Dictionary = s2.snapshot()
	# Compare the deterministic fields.
	assert_eq(snap2["version"], snap["version"])
	assert_eq(snap2["wave"], snap["wave"])
	assert_eq(snap2["score"], snap["score"])
	assert_eq(snap2["lives"], snap["lives"])
	assert_almost_eq(snap2["formation"]["ox"], snap["formation"]["ox"], 1e-6)
	assert_eq(snap2["enemies"], snap["enemies"])
	assert_eq(snap2["bunkers"].size(), snap["bunkers"].size())
	for i in range(snap["bunkers"].size()):
		assert_eq(snap2["bunkers"][i], snap["bunkers"][i], "bunker %d differs" % i)
	assert_eq(snap2["player_bullet"]["alive"], snap["player_bullet"]["alive"])


func test_reserved_divers_and_rng_dive_present() -> void:
	var s = State.create(0, _cfg(), _lvl())
	var snap: Dictionary = s.snapshot()
	# v1 always emits these so that the dive PR can populate without
	# bumping `version`.
	assert_eq(snap["divers"], [])
	assert_true(snap.has("rng_dive"))


func test_tunneling_cap_violation_returns_null() -> void:
	# Crank player bullet speed so that one sub-step (16 ms) exceeds the
	# smallest collidable feature, forcing the cap to refuse.
	var c: Cfg = _cfg()
	# At 16 ms sub-step, a speed of 1500 px/s travels 24 px > player_h (8).
	c.player_bullet_speed = 1500.0
	var s = State.create(0, c, _lvl())
	assert_null(s)
	# create() should have emitted a push_error explaining the violation.
	assert_push_error("tunneling cap violated")


func test_sub_rng_independence_dive_does_not_perturb_bullet() -> void:
	# Two states with same master seed; consume from `_dive_rng` on one of
	# them. The bullet stream must be unaffected (acceptance #14).
	var s1 = State.create(99, _cfg(), _lvl())
	var s2 = State.create(99, _cfg(), _lvl())
	# Drain a few values from s2's dive rng (simulating dive PR's consumer).
	for _i in range(50):
		s2._dive_rng.randi()
	# Both must emit identical bullet RNG draws.
	for _i in range(20):
		assert_eq(s1._bullet_rng.randi(), s2._bullet_rng.randi())
