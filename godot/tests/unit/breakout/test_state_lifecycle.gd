extends GutTest
## BreakoutGameState lifecycle — sticky/launch, life loss, win/lose, snapshot.

const BreakoutConfig := preload("res://scripts/breakout/core/breakout_config.gd")
const BreakoutLevel := preload("res://scripts/breakout/core/breakout_level.gd")
const BreakoutState := preload("res://scripts/breakout/core/breakout_state.gd")


func _level_with(cells: Array, rows: int = 1, cols: int = 1) -> BreakoutLevel:
	var lvl: BreakoutLevel = BreakoutLevel.new()
	lvl.rows = rows
	lvl.cols = cols
	lvl.brick_w = 20.0
	lvl.brick_h = 10.0
	lvl.origin_x = 100.0
	lvl.origin_y = 100.0
	lvl.cells = cells
	return lvl


func _cfg() -> BreakoutConfig:
	var c: BreakoutConfig = BreakoutConfig.new()
	c.ball_speed_start = 100.0
	c.lives_start = 3
	return c


# --- Sticky / launch ---

func test_initial_mode_is_sticky() -> void:
	var s: BreakoutState = BreakoutState.create(1, _cfg(), _level_with([{"hp": 0}]))
	assert_eq(s.mode, BreakoutState.Mode.STICKY)
	assert_eq(s.lives, 3)
	assert_eq(s.score, 0)


func test_launch_leaves_sticky_with_nonzero_velocity() -> void:
	var s: BreakoutState = BreakoutState.create(1, _cfg(), _level_with([{"hp": 0}]))
	s.launch()
	assert_eq(s.mode, BreakoutState.Mode.LIVE)
	var speed_sq: float = s.ball_vx * s.ball_vx + s.ball_vy * s.ball_vy
	assert_almost_eq(sqrt(speed_sq), s.config.ball_speed_start, 1e-3)
	assert_lt(s.ball_vy, 0.0, "initial flight is upward")


func test_launch_is_idempotent_when_live() -> void:
	var s: BreakoutState = BreakoutState.create(1, _cfg(), _level_with([{"hp": 0}]))
	s.launch()
	var vx_before: float = s.ball_vx
	var vy_before: float = s.ball_vy
	s.launch()  # should be a no-op
	assert_eq(s.ball_vx, vx_before)
	assert_eq(s.ball_vy, vy_before)


# --- Life loss + sticky respawn (acceptance #6) ---

func test_life_loss_respawns_sticky() -> void:
	var s: BreakoutState = BreakoutState.create(1, _cfg(), _level_with([{"hp": 0}]))
	s.launch()
	# Place ball below world, descending.
	s.ball_y = s.config.world_h + 10.0
	s.ball_vx = 50.0
	s.ball_vy = 100.0
	s.mode = BreakoutState.Mode.LIVE
	# Initialize clock then step once.
	s.tick(0)
	s.tick(s.config.step_dt_ms)
	assert_eq(s.lives, 2)
	assert_eq(s.mode, BreakoutState.Mode.STICKY)
	# Ball reset to above paddle, velocity zero.
	assert_eq(s.ball_vx, 0.0)
	assert_eq(s.ball_vy, 0.0)
	assert_almost_eq(s.ball_x, s.paddle_x, 1e-3)


func test_life_loss_at_zero_lives_is_game_over() -> void:
	var cfg: BreakoutConfig = _cfg()
	cfg.lives_start = 1
	var s: BreakoutState = BreakoutState.create(1, cfg, _level_with([{"hp": 0}]))
	s.launch()
	s.ball_y = s.config.world_h + 10.0
	s.ball_vx = 0.0
	s.ball_vy = 100.0
	s.mode = BreakoutState.Mode.LIVE
	s.tick(0)
	s.tick(s.config.step_dt_ms)
	assert_eq(s.lives, 0)
	assert_true(s.is_game_over())


# --- Win condition (acceptance #7) ---

func test_win_when_last_destructible_brick_destroyed() -> void:
	# Single destructible brick with hp=1; aim ball straight at it.
	var lvl: BreakoutLevel = _level_with([
		{"hp": 1, "value": 100, "destructible": true, "color_id": 0},
	])
	var s: BreakoutState = BreakoutState.create(1, _cfg(), lvl)
	s.launch()
	# Brick centre = (100+10, 100+5) = (110, 105). Place ball just below it.
	s.ball_x = 110.0
	s.ball_y = 105.0 + 5.0 + s.config.ball_radius + 0.5
	s.ball_vx = 0.0
	s.ball_vy = -s.config.ball_speed_start
	s.mode = BreakoutState.Mode.LIVE
	s.tick(0)
	# A few sub-steps to ensure the ball reaches and hits the brick.
	for i in 5:
		s.tick((i + 1) * s.config.step_dt_ms)
	assert_eq(int(s.bricks[0]["hp"]), 0)
	assert_eq(s.score, 100)
	assert_true(s.is_won())


func test_indestructible_brick_does_not_block_win() -> void:
	# One destructible + one indestructible. Win requires only that all
	# destructible bricks be cleared.
	var lvl: BreakoutLevel = _level_with([
		{"hp": 1, "value": 100, "destructible": true, "color_id": 0},
		{"hp": 99, "value": 0, "destructible": false, "color_id": 1},
	], 1, 2)
	var s: BreakoutState = BreakoutState.create(1, _cfg(), lvl)
	# Manually destroy the destructible brick by zeroing its hp.
	s.bricks[0]["hp"] = 0
	# Step to trigger win check via _step.
	# But: win check only fires inside a brick-collision branch. We need to
	# trigger it. Easiest: call the helper directly (private — ok in test).
	assert_true(s._all_destructibles_cleared())


# --- Snapshot (acceptance #10) ---

func test_snapshot_has_version_and_drops_destroyed_bricks() -> void:
	var lvl: BreakoutLevel = _level_with([
		{"hp": 1, "value": 100, "destructible": true, "color_id": 0},
		{"hp": 2, "value": 200, "destructible": true, "color_id": 1},
	], 1, 2)
	var s: BreakoutState = BreakoutState.create(1, _cfg(), lvl)
	# Destroy brick 0 manually; snapshot should omit it.
	s.bricks[0]["hp"] = 0
	var snap: Dictionary = s.snapshot()
	assert_eq(int(snap["version"]), 1)
	# Bricks list omits the dead brick.
	var bricks_out: Array = snap["bricks"]
	assert_eq(bricks_out.size(), 1)
	assert_eq(int(bricks_out[0]["idx"]), 1)
	assert_eq(int(bricks_out[0]["hp"]), 2)


# --- tick() returns bool (acceptance #10) ---

func test_tick_returns_false_on_first_call() -> void:
	# First tick just aligns the clock — no sub-steps fire.
	var s: BreakoutState = BreakoutState.create(1, _cfg(), _level_with([{"hp": 0}]))
	assert_false(s.tick(123))


func test_tick_returns_true_when_ball_moves() -> void:
	var s: BreakoutState = BreakoutState.create(1, _cfg(), _level_with([{"hp": 0}]))
	s.launch()
	s.tick(0)
	# 10 ms = 1 sub-step; ball moves.
	assert_true(s.tick(s.config.step_dt_ms))


func test_tick_caps_substeps() -> void:
	# Pass a now_ms 1 second after t=0 → that's 100 sub-steps worth, but
	# max_steps_per_tick caps at 8. After cap, accum should be drained.
	var s: BreakoutState = BreakoutState.create(1, _cfg(), _level_with([{"hp": 0}]))
	s.tick(0)
	s.tick(1000)
	assert_lt(s.accum_ms, s.config.step_dt_ms)


# --- Determinism (acceptance #1, #8) ---

func test_same_seed_same_inputs_same_state() -> void:
	var lvl_a: BreakoutLevel = _level_with([
		{"hp": 1, "value": 100, "destructible": true, "color_id": 0},
	])
	var lvl_b: BreakoutLevel = _level_with([
		{"hp": 1, "value": 100, "destructible": true, "color_id": 0},
	])
	var a: BreakoutState = BreakoutState.create(42, _cfg(), lvl_a)
	var b: BreakoutState = BreakoutState.create(42, _cfg(), lvl_b)
	a.launch()
	b.launch()
	# Same seed → same launch bias.
	assert_almost_eq(a.ball_vx, b.ball_vx, 1e-9)
	assert_almost_eq(a.ball_vy, b.ball_vy, 1e-9)
	# Drive same intent and same time stamps; snapshots should match.
	a.tick(0); b.tick(0)
	a.set_paddle_intent(50.0); b.set_paddle_intent(50.0)
	for i in 20:
		var t: int = (i + 1) * a.config.step_dt_ms
		a.tick(t); b.tick(t)
	assert_eq(a.snapshot(), b.snapshot())


# --- Paddle intent clamping ---

func test_paddle_intent_clamps_to_max_speed() -> void:
	var s: BreakoutState = BreakoutState.create(1, _cfg(), _level_with([{"hp": 0}]))
	s.set_paddle_intent(99999.0)
	assert_eq(s.paddle_intent_vx, s.config.paddle_max_speed_px_s)
	s.set_paddle_intent(-99999.0)
	assert_eq(s.paddle_intent_vx, -s.config.paddle_max_speed_px_s)
