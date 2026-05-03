extends GutTest
## Integration: scripted seed + intent + ticks → expected snapshot stream.
## Bypasses the scene + input layer entirely; drives BreakoutGameState
## directly. Catches non-determinism that the scene test can't surface
## because of wall-clock timing.

const BreakoutConfig := preload("res://scripts/breakout/core/breakout_config.gd")
const BreakoutLevel := preload("res://scripts/breakout/core/breakout_level.gd")
const BreakoutGameState := preload("res://scripts/breakout/core/breakout_state.gd")

const SEED: int = 4242

func _make_level() -> BreakoutLevel:
	# Tiny 2×2 destructible grid for fast termination.
	var lvl := BreakoutLevel.new()
	lvl.rows = 2
	lvl.cols = 2
	lvl.brick_w = 40.0
	lvl.brick_h = 16.0
	lvl.origin_x = 80.0
	lvl.origin_y = 30.0
	lvl.cells = [
		{"hp": 1, "value": 100, "destructible": true, "color_id": 0},
		{"hp": 1, "value": 100, "destructible": true, "color_id": 1},
		{"hp": 1, "value": 100, "destructible": true, "color_id": 2},
		{"hp": 1, "value": 100, "destructible": true, "color_id": 3},
	]
	return lvl

func _make_state() -> BreakoutGameState:
	var cfg := BreakoutConfig.new()
	return BreakoutGameState.create(SEED, cfg, _make_level())


func test_same_seed_same_intents_same_snapshot_stream() -> void:
	# Two parallel runs with identical inputs should produce byte-identical
	# snapshot streams.
	var a := _make_state()
	var b := _make_state()
	a.launch()
	b.launch()
	var snaps_a: Array[Dictionary] = []
	var snaps_b: Array[Dictionary] = []
	for i in 200:
		# Apply a paddle-intent oscillation that exercises clamp + reflection.
		var intent: float = 120.0 if (i % 60) < 30 else -120.0
		a.set_paddle_intent(intent)
		b.set_paddle_intent(intent)
		var t: int = i * 16
		a.tick(t)
		b.tick(t)
		snaps_a.append(a.snapshot())
		snaps_b.append(b.snapshot())
	assert_eq(snaps_a, snaps_b, "snapshot streams must match for identical seed+intents")


func test_session_with_paddle_off_screen_ends_in_game_over() -> void:
	# One-life run with paddle parked in a corner: ball falls past it and
	# lives drain to zero. Bounds iteration count so a regression doesn't
	# hang the suite. Confirms: launch → ball motion → life loss → LOST.
	var cfg := BreakoutConfig.new()
	cfg.lives_start = 1
	var s := BreakoutGameState.create(SEED, cfg, _make_level())
	s.paddle_x = 0.0
	s.launch()
	var step: int = 0
	var t: int = 0
	while not s.is_game_over() and step < 5000:
		t += 16
		s.tick(t)
		step += 1
	assert_true(s.is_game_over(), "session ends in LOST mode when paddle is parked")
	assert_eq(s.lives, 0, "lives drain to zero")


func test_snapshot_carries_version() -> void:
	var s := _make_state()
	var snap: Dictionary = s.snapshot()
	assert_eq(int(snap.get("version", -1)), BreakoutGameState.SCHEMA_VERSION,
		"snapshot must carry schema version")


func test_set_paddle_intent_clamped_to_max() -> void:
	# Acceptance: clamp at apply, so a huge intent doesn't bypass max_speed.
	var s := _make_state()
	s.set_paddle_intent(99999.0)
	assert_almost_eq(s.paddle_intent_vx, s.config.paddle_max_speed_px_s, 0.001)
	s.set_paddle_intent(-99999.0)
	assert_almost_eq(s.paddle_intent_vx, -s.config.paddle_max_speed_px_s, 0.001)
