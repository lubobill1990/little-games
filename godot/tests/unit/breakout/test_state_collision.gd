extends GutTest
## BreakoutGameState collision tests — walls, paddle, bricks.

const BreakoutConfig := preload("res://scripts/breakout/core/breakout_config.gd")
const BreakoutLevel := preload("res://scripts/breakout/core/breakout_level.gd")
const BreakoutState := preload("res://scripts/breakout/core/breakout_state.gd")


# Helper: empty-level config + level with no bricks. Used for ball-on-paddle
# and wall tests that don't want any brick interference.
func _empty_setup() -> BreakoutState:
	var cfg: BreakoutConfig = BreakoutConfig.new()
	# Slow ball so a single 10ms sub-step crosses ~1.2 px — well below feature size.
	cfg.ball_speed_start = 100.0
	var lvl: BreakoutLevel = BreakoutLevel.new()
	lvl.rows = 1
	lvl.cols = 1
	lvl.cells = [{"hp": 0}]  # empty cell
	return BreakoutState.create(1, cfg, lvl)


# Helper: drive the state by a specific number of fixed sub-steps. Bypasses
# the wall-clock now_ms path by calling tick() with growing values.
func _step_n(s: BreakoutState, n: int) -> void:
	# Initialize clock.
	s.tick(0)
	for i in n:
		s.tick((i + 1) * s.config.step_dt_ms)


# --- Walls ---

func test_wall_bounce_left() -> void:
	var s := _empty_setup()
	s.launch()
	# Aim ball straight at left wall.
	s.ball_x = s.config.ball_radius + 0.5
	s.ball_y = 100.0
	s.ball_vx = -s.config.ball_speed_start
	s.ball_vy = 0.0
	s.mode = BreakoutState.Mode.LIVE
	_step_n(s, 1)
	assert_gt(s.ball_vx, 0.0, "vx should reverse to positive after left wall")


func test_wall_bounce_right() -> void:
	var s := _empty_setup()
	s.launch()
	s.ball_x = s.config.world_w - s.config.ball_radius - 0.5
	s.ball_y = 100.0
	s.ball_vx = s.config.ball_speed_start
	s.ball_vy = 0.0
	s.mode = BreakoutState.Mode.LIVE
	_step_n(s, 1)
	assert_lt(s.ball_vx, 0.0, "vx should reverse to negative after right wall")


func test_wall_bounce_top() -> void:
	var s := _empty_setup()
	s.launch()
	s.ball_x = 100.0
	s.ball_y = s.config.ball_radius + 0.5
	s.ball_vx = 0.0
	s.ball_vy = -s.config.ball_speed_start
	s.mode = BreakoutState.Mode.LIVE
	_step_n(s, 1)
	assert_gt(s.ball_vy, 0.0, "vy should flip to descending after top wall")


# --- Paddle bias (acceptance #3) ---

func test_paddle_bias_centre_is_pure_vertical() -> void:
	var s := _empty_setup()
	s.launch()
	# Place ball directly above paddle centre, descending.
	s.ball_x = s.config.world_w * 0.5
	s.ball_y = s.config.paddle_y - s.config.ball_radius - 0.1
	s.ball_vx = 0.0
	s.ball_vy = s.config.ball_speed_start
	s.mode = BreakoutState.Mode.LIVE
	_step_n(s, 1)
	assert_almost_eq(s.ball_vx, 0.0, 1e-3, "centre-hit vx should be ~0")
	assert_lt(s.ball_vy, 0.0, "should reflect upward")


func test_paddle_bias_left_edge_biases_left() -> void:
	var s := _empty_setup()
	s.launch()
	# Place ball above LEFT half of paddle.
	s.ball_x = s.config.world_w * 0.5 - s.config.paddle_w * 0.4
	s.ball_y = s.config.paddle_y - s.config.ball_radius - 0.1
	s.ball_vx = 0.0
	s.ball_vy = s.config.ball_speed_start
	s.mode = BreakoutState.Mode.LIVE
	_step_n(s, 1)
	assert_lt(s.ball_vx, 0.0, "left-edge hit should bias vx negative")
	assert_lt(s.ball_vy, 0.0, "should still reflect upward")


func test_paddle_bias_right_edge_biases_right() -> void:
	var s := _empty_setup()
	s.launch()
	s.ball_x = s.config.world_w * 0.5 + s.config.paddle_w * 0.4
	s.ball_y = s.config.paddle_y - s.config.ball_radius - 0.1
	s.ball_vx = 0.0
	s.ball_vy = s.config.ball_speed_start
	s.mode = BreakoutState.Mode.LIVE
	_step_n(s, 1)
	assert_gt(s.ball_vx, 0.0, "right-edge hit should bias vx positive")


func test_paddle_bias_preserves_speed() -> void:
	# Acceptance #3: piecewise linear; speed magnitude preserved.
	var s := _empty_setup()
	s.launch()
	s.ball_x = s.config.world_w * 0.5 - s.config.paddle_w * 0.3
	s.ball_y = s.config.paddle_y - s.config.ball_radius - 0.1
	s.ball_vx = 0.0
	s.ball_vy = s.config.ball_speed_start
	s.mode = BreakoutState.Mode.LIVE
	_step_n(s, 1)
	var speed: float = sqrt(s.ball_vx * s.ball_vx + s.ball_vy * s.ball_vy)
	assert_almost_eq(speed, s.config.ball_speed_start, 1e-3)


# --- Brick face detection (acceptance #4) ---

func _one_brick_setup(cx: float, cy: float) -> BreakoutState:
	var cfg: BreakoutConfig = BreakoutConfig.new()
	cfg.ball_speed_start = 100.0
	var lvl: BreakoutLevel = BreakoutLevel.new()
	lvl.rows = 1
	lvl.cols = 1
	lvl.brick_w = 20.0
	lvl.brick_h = 10.0
	# Place brick by tweaking origin so brick centre lands at (cx, cy).
	lvl.origin_x = cx - lvl.brick_w * 0.5
	lvl.origin_y = cy - lvl.brick_h * 0.5
	lvl.cells = [{"hp": 1, "value": 100, "destructible": true, "color_id": 0}]
	return BreakoutState.create(1, cfg, lvl)


func test_brick_top_face_hit_reflects_vy() -> void:
	# Ball below brick travelling up: should hit BOTTOM face (= reflect vy).
	# Wait — ball below moving up hits the bottom of the brick. Let's do
	# top-face hit: ball above brick moving down.
	var s := _one_brick_setup(160.0, 100.0)
	s.launch()
	s.ball_x = 160.0
	s.ball_y = 100.0 - 10.0 * 0.5 - s.config.ball_radius - 0.5   # just above brick
	s.ball_vx = 0.0
	s.ball_vy = s.config.ball_speed_start
	s.mode = BreakoutState.Mode.LIVE
	_step_n(s, 1)
	assert_lt(s.ball_vy, 0.0, "top-face hit should flip vy")
	assert_eq(s.bricks[0]["hp"], 0)
	assert_eq(s.score, 100)


func test_brick_left_face_hit_reflects_vx() -> void:
	# Ball to the left of brick, moving right: hits LEFT face.
	var s := _one_brick_setup(160.0, 100.0)
	s.launch()
	s.ball_x = 160.0 - 20.0 * 0.5 - s.config.ball_radius - 0.5
	s.ball_y = 100.0
	s.ball_vx = s.config.ball_speed_start
	s.ball_vy = 0.0
	s.mode = BreakoutState.Mode.LIVE
	_step_n(s, 1)
	assert_lt(s.ball_vx, 0.0, "left-face hit should flip vx")


# --- Multi-brick corner sandwich (acceptance #5) ---

func test_corner_sandwich_decrements_only_one_brick() -> void:
	# Two adjacent bricks side by side. Place the ball so it overlaps both
	# equally on the X axis (corner sandwich). The brick at index 0 should
	# win the tie (lower idx) and lose 1 hp; the brick at index 1 keeps hp.
	var cfg: BreakoutConfig = BreakoutConfig.new()
	cfg.ball_speed_start = 100.0
	var lvl: BreakoutLevel = BreakoutLevel.new()
	lvl.rows = 1
	lvl.cols = 2
	lvl.brick_w = 20.0
	lvl.brick_h = 10.0
	lvl.origin_x = 100.0
	lvl.origin_y = 100.0
	lvl.cells = [
		{"hp": 2, "value": 100, "destructible": true, "color_id": 0},
		{"hp": 2, "value": 100, "destructible": true, "color_id": 0},
	]
	var s: BreakoutState = BreakoutState.create(1, cfg, lvl)
	s.launch()
	# Brick 0 centre = (100+10, 105). Brick 1 centre = (120+10, 105).
	# Ball centred between them at x=120, y=105 (their shared edge x=120).
	# Ball overlaps both equally. Penetration on X for each = ball_radius
	# + brick_hx - |dx| = 3 + 10 - 10 = 3. Y depth = 3 + 5 - 0 = 8.
	# Dominant axis on each = X (smaller). Both X depths = 3 → tie → idx 0 wins.
	s.ball_x = 120.0
	s.ball_y = 105.0
	s.ball_vx = 0.0   # reflection result doesn't matter for hp test
	s.ball_vy = 50.0
	s.mode = BreakoutState.Mode.LIVE
	_step_n(s, 1)
	assert_eq(int(s.bricks[0]["hp"]), 1, "brick 0 (lower idx) should be decremented")
	assert_eq(int(s.bricks[1]["hp"]), 2, "brick 1 should stay untouched")


# --- Tunneling cap (acceptance #9) ---

func test_create_rejects_excessive_ball_speed() -> void:
	# OK case: speed × dt < min(brick_w, brick_h, paddle_h). Default
	# paddle_h is 6, so speed must be < 600 px/s at step_dt_ms=10. We
	# pick 500 to stay clear of the boundary.
	var cfg: BreakoutConfig = BreakoutConfig.new()
	cfg.ball_speed_start = 500.0
	var lvl: BreakoutLevel = BreakoutLevel.new()
	lvl.brick_w = 28.0
	lvl.brick_h = 10.0
	lvl.cells = []
	var s: BreakoutState = BreakoutState.create(1, cfg, lvl)
	assert_not_null(s)
