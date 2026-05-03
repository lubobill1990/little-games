extends GutTest
## InvadersGameState — collisions, formation step, wave progression,
## loss conditions, UFO behaviour.

const State := preload("res://scripts/invaders/core/invaders_state.gd")
const Cfg := preload("res://scripts/invaders/core/invaders_config.gd")
const Lvl := preload("res://scripts/invaders/core/invaders_level.gd")
const Formation := preload("res://scripts/invaders/core/formation.gd")


func _cfg() -> Cfg:
	return Cfg.new()


func _lvl() -> Lvl:
	return Lvl.new()


# --- Formation step + edge bounce ---

func test_formation_step_shifts_origin() -> void:
	var s = State.create(0, _cfg(), _lvl())
	# Force a step by manipulating the accumulator + step_ms.
	s.formation_step_ms_accum = s.formation_step_ms
	var ox_before: float = s.formation_ox
	s._step_formation()
	assert_almost_eq(s.formation_ox, ox_before + s.config.step_dx, 1e-6)


func test_formation_edge_bounce_reverses_and_drops() -> void:
	var c: Cfg = _cfg()
	c.world_w = 100.0
	c.formation_start_x = 80.0  # Right edge near world.right
	c.cell_w = 4.0
	c.cell_h = 4.0
	c.cols = 5
	c.rows = 1
	c.enemy_hx = 1.0
	c.step_dx = 4.0
	c.step_dy = 8.0
	var s = State.create(0, c, _lvl())
	# Single row of 5 cells: rightmost center = 80 + 4*4 + 2 = 98; right
	# edge after extents = 99. Step right by 4 → 103 → past world.right.
	# Must reverse + drop.
	var oy_before: float = s.formation_oy
	var ox_before: float = s.formation_ox
	var dir_before: int = s.formation_dir
	s._step_formation()
	assert_eq(s.formation_dir, -dir_before, "direction reversed")
	assert_almost_eq(s.formation_oy, oy_before + c.step_dy, 1e-6)
	# ox stays put on bounce frame.
	assert_almost_eq(s.formation_ox, ox_before, 1e-6)


# --- Player bullet vs enemies ---

func test_fire_then_hit_increments_score() -> void:
	var c: Cfg = _cfg()
	c.player_bullet_speed = 5000.0  # ridiculously fast → next sub-step the
	# bullet should fly past the formation if we don't hit. But we *do*
	# want a hit, so position it precisely.
	# Set tunneling cap loosely: feature ≥ step_dist. With 16 ms sub-step,
	# 5000 * 0.016 = 80; so cell_h must be ≥ 80. Bump.
	c.cell_h = 100.0
	c.enemy_hy = 50.0
	c.player_bullet_h = 100.0
	c.player_h = 100.0
	c.bunker_cell_h = 100.0
	var s = State.create(0, c, _lvl())
	# Place bullet just below row 4 of column 5 (center of formation).
	s.player_bullet_alive = true
	var col: int = 5
	var row: int = 4
	s.player_bullet_x = s.formation_ox + col * c.cell_w + c.cell_w * 0.5
	s.player_bullet_y = s.formation_oy + row * c.cell_h + c.cell_h * 0.5
	var hit: bool = s._player_bullet_vs_enemies()
	assert_true(hit)
	assert_eq(s.live_mask[row * c.cols + col], 0)
	assert_false(s.player_bullet_alive)
	# Score should now be > 0 (row 4 → kind index from level row_kinds[4]=0
	# → row_values[0] = 30 by our default).
	assert_gt(s.score, 0)


# --- Enemy bullet cap ---

func test_enemy_bullet_cap_initial_wave() -> void:
	var s = State.create(0, _cfg(), _lvl())
	# Cap at wave 1 = enemy_bullets_max_init.
	assert_eq(s._max_enemy_bullets(), s.config.enemy_bullets_max_init)


func test_enemy_bullet_cap_grows_with_wave() -> void:
	var s = State.create(0, _cfg(), _lvl())
	s.wave = 3
	# +1 per wave step (default wave_step=1, per_wave=1) → init + 2.
	assert_eq(s._max_enemy_bullets(),
			s.config.enemy_bullets_max_init + 2 * s.config.enemy_bullets_per_wave)


func test_spawn_enemy_bullet_uses_bottom_of_column() -> void:
	var s = State.create(0, _cfg(), _lvl())
	# Force the bullet RNG into a state where the seeded column has a known
	# bottom row. Easier: kill all of row 4 entirely, so any column's
	# bottom is row 3.
	for c in range(s.config.cols):
		s.live_mask[4 * s.config.cols + c] = 0
	var ok: bool = s._spawn_enemy_bullet()
	assert_true(ok)
	# The new bullet's y should equal: formation_oy + 3*cell_h + cell_h/2 +
	# enemy_hy + bullet_h/2 + epsilon.
	var bullet: Dictionary = s.enemy_bullets[s.enemy_bullets.size() - 1]
	var expected_min_y: float = s.formation_oy + 3.0 * s.config.cell_h + s.config.cell_h * 0.5 + s.config.enemy_hy
	assert_gt(float(bullet["y"]), expected_min_y - 0.001)


# --- Loss conditions ---

func test_loss_by_lives_zero() -> void:
	var s = State.create(0, _cfg(), _lvl())
	s.lives = 0
	assert_true(s.is_game_over())


func test_loss_by_formation_reaching_player() -> void:
	var s = State.create(0, _cfg(), _lvl())
	# Drop the formation so its bottom enemies sit on top of the player.
	s.formation_oy = s.config.player_y - s.config.player_h * 0.5 \
			- s.config.cell_h * (s.config.rows - 1) - s.config.cell_h * 0.5 \
			- s.config.enemy_hy + 10.0
	# This places bottom row's center near player; bounds_y bottom should
	# exceed player_top.
	assert_true(s.is_game_over())


# --- Wave progression ---

func test_wave_progression_clears_formation_and_increases_wave() -> void:
	var s = State.create(0, _cfg(), _lvl())
	# Kill everyone.
	for i in range(s.live_mask.size()):
		s.live_mask[i] = 0
	# Set up a UFO so we can verify it's cleared.
	s.ufo_alive = true
	s.ufo_x = 50.0
	s._advance_wave()
	assert_eq(s.wave, 2)
	# Formation refilled.
	var live: int = 0
	for i in range(s.live_mask.size()):
		live += s.live_mask[i]
	assert_eq(live, s.config.rows * s.config.cols)
	# UFO removed.
	assert_false(s.ufo_alive)
	# Speed faster: step_ms_init * factor < step_ms_init.
	assert_lt(s.formation_step_ms, s.config.step_ms_init)


# --- UFO ---

func test_ufo_spawn_off_left_or_right_edge() -> void:
	var s = State.create(0, _cfg(), _lvl())
	# Force a spawn by setting last_ufo_spawn_ms way back.
	s.last_tick_ms = 100000
	s.last_ufo_spawn_ms = 0
	# step_ufo with a bigger dt to trigger the should_spawn path.
	var changed: bool = s._step_ufo(0.016, 16)
	# Either spawned or didn't (depends on rng); if spawned, x must be at
	# either edge.
	if s.ufo_alive:
		assert_true(changed)
		var hw: float = s.config.ufo_w * 0.5
		assert_true(s.ufo_x <= -hw + 0.001 or s.ufo_x >= s.config.world_w + hw - 0.001)


func test_ufo_offscreen_removes_without_score() -> void:
	var s = State.create(0, _cfg(), _lvl())
	s.ufo_alive = true
	s.ufo_dir = 1
	s.ufo_x = s.config.world_w + s.config.ufo_w  # already past right edge
	var score_before: int = s.score
	s._step_ufo(0.001, 1)
	assert_false(s.ufo_alive)
	assert_eq(s.score, score_before)


func test_ufo_hit_by_player_bullet_awards_table_score() -> void:
	var c: Cfg = _cfg()
	# Loosen tunneling cap.
	c.player_bullet_speed = 100.0
	var s = State.create(0, c, _lvl())
	s.ufo_alive = true
	s.ufo_x = 100.0
	# Place bullet on top of UFO.
	s.player_bullet_alive = true
	s.player_bullet_x = s.ufo_x
	s.player_bullet_y = c.ufo_y
	var hit: bool = s._player_bullet_vs_ufo()
	assert_true(hit)
	assert_false(s.ufo_alive)
	assert_false(s.player_bullet_alive)
	# Score is one of the deterministic table.
	var v: int = s.score
	assert_true(v == 50 or v == 100 or v == 150 or v == 300, "got %d" % v)
