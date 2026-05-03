extends GutTest
## Integration test: scripted player-intent log against InvadersGameState
## with a fixed seed → asserts deterministic snapshot stream from core.
## Pure-core (no scene); the scene test covers wiring.

const InvadersConfig := preload("res://scripts/invaders/core/invaders_config.gd")
const InvadersLevel := preload("res://scripts/invaders/core/invaders_level.gd")
const InvadersGameState := preload("res://scripts/invaders/core/invaders_state.gd")

const SEED_A: int = 0xA1
const SEED_B: int = 0xB2


func _make_state(seed_value: int) -> InvadersGameState:
	var cfg: InvadersConfig = InvadersConfig.new()
	var lvl: InvadersLevel = InvadersLevel.new()
	return InvadersGameState.create(seed_value, cfg, lvl)


func test_same_seed_same_snapshot_stream() -> void:
	# Same seed + same input log = identical snapshots at each tick.
	var s1: InvadersGameState = _make_state(SEED_A)
	var s2: InvadersGameState = _make_state(SEED_A)
	var t: int = 0
	for i in range(120):
		t += 16
		s1.set_player_intent(0.0)
		s2.set_player_intent(0.0)
		s1.tick(t)
		s2.tick(t)
	var sn1: Dictionary = s1.snapshot()
	var sn2: Dictionary = s2.snapshot()
	assert_eq(sn1["score"], sn2["score"])
	assert_eq(sn1["wave"], sn2["wave"])
	assert_eq(sn1["lives"], sn2["lives"])
	assert_eq(sn1["formation"]["ox"], sn2["formation"]["ox"])
	assert_eq(sn1["formation"]["oy"], sn2["formation"]["oy"])
	# Compare PackedByteArray contents element-wise.
	var e1: PackedByteArray = sn1["enemies"]
	var e2: PackedByteArray = sn2["enemies"]
	assert_eq(e1.size(), e2.size())
	for i in range(e1.size()):
		assert_eq(e1[i], e2[i])


func test_different_seed_diverges() -> void:
	# Distinct seeds eventually produce a different state — at minimum, the
	# UFO RNG diverges, so over many ticks at least one snapshot field
	# differs. We just assert the snapshots aren't trivially identical.
	var s1: InvadersGameState = _make_state(SEED_A)
	var s2: InvadersGameState = _make_state(SEED_B)
	var t: int = 0
	for i in range(2000):
		t += 16
		s1.tick(t)
		s2.tick(t)
	var sn1: Dictionary = s1.snapshot()
	var sn2: Dictionary = s2.snapshot()
	# Either RNG state diverged or some derived field did.
	assert_ne(sn1["rng_bullet"], sn2["rng_bullet"],
		"bullet RNG state diverges across seeds")


func test_fire_intent_log_produces_player_bullet() -> void:
	# Scripted log: t=100ms fire, expect a bullet to appear and travel up.
	var s: InvadersGameState = _make_state(SEED_A)
	s.tick(0)
	s.tick(50)
	assert_false(s.player_bullet_alive, "no bullet before fire")
	var fired: bool = s.fire()
	assert_true(fired, "fire() returns true on first call")
	assert_true(s.player_bullet_alive)
	var fired_again: bool = s.fire()
	assert_false(fired_again, "second fire() returns false while bullet alive")
	# Tick forward; bullet y must decrease (travels up).
	var by0: float = s.player_bullet_y
	s.tick(150)
	assert_lt(s.player_bullet_y, by0, "player bullet moves up after tick")


func test_set_last_tick_prevents_simulation_burst() -> void:
	# Simulating a long pause: pre-pause tick at 100ms, then "wake up" at
	# 5000ms via set_last_tick(5000); the very next tick at 5016ms must
	# NOT step the formation 4900ms forward.
	var s: InvadersGameState = _make_state(SEED_A)
	s.tick(0)
	s.tick(100)
	var ox_before: float = s.formation_ox
	s.set_last_tick(5000)
	# A very small dt: 16ms. Should at most produce one sub-step worth of motion.
	s.tick(5016)
	var dx: float = absf(s.formation_ox - ox_before)
	# step_dx is config.step_dx (8.0). After only 16 ms there cannot have
	# been more than zero or one formation steps regardless of cadence.
	assert_lt(dx, 8.5, "set_last_tick suppressed catch-up auto-step")


func test_wave_advances_when_all_enemies_killed() -> void:
	# Scripted: clear the formation directly, advance one tick, expect wave += 1.
	var s: InvadersGameState = _make_state(SEED_A)
	s.tick(0)
	for i in range(s.live_mask.size()):
		s.live_mask[i] = 0
	# tick must process the empty-formation → _advance_wave path.
	s.tick(16)
	assert_eq(s.wave, 2, "wave advances when formation cleared")
	# Live count must be back to full (fresh wave).
	var live: int = 0
	for i in range(s.live_mask.size()):
		if s.live_mask[i] == 1:
			live += 1
	assert_eq(live, s.config.rows * s.config.cols,
		"new wave repopulates the formation")
