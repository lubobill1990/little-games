extends GutTest
## formation.gd — bounds, live count, speed curve, firing column.

const Formation := preload("res://scripts/invaders/core/formation.gd")


func _full_mask(rows: int, cols: int) -> PackedByteArray:
	var m: PackedByteArray = PackedByteArray()
	m.resize(rows * cols)
	for i in range(m.size()):
		m[i] = 1
	return m


func test_bounds_x_full_grid() -> void:
	# 5x11 grid, cell_w=16, ox=16, enemy_hx=6
	# Leftmost cell center = 16 + 0*16 + 8 = 24; left edge = 24-6 = 18
	# Rightmost center = 16 + 10*16 + 8 = 184; right edge = 184+6 = 190
	var m: PackedByteArray = _full_mask(5, 11)
	var b: Vector2 = Formation.bounds_x(m, 5, 11, 16.0, 40.0, 16.0, 14.0, 6.0)
	assert_almost_eq(b.x, 18.0, 1e-6)
	assert_almost_eq(b.y, 190.0, 1e-6)


func test_bounds_x_after_killing_outer_columns() -> void:
	# Kill all of col 0 and col 10 — leftmost should now be col 1.
	var m: PackedByteArray = _full_mask(5, 11)
	for r in range(5):
		m[r * 11 + 0] = 0
		m[r * 11 + 10] = 0
	var b: Vector2 = Formation.bounds_x(m, 5, 11, 16.0, 40.0, 16.0, 14.0, 6.0)
	# col 1 center = 16 + 16 + 8 = 40; left = 34
	# col 9 center = 16 + 9*16 + 8 = 168; right = 174
	assert_almost_eq(b.x, 34.0, 1e-6)
	assert_almost_eq(b.y, 174.0, 1e-6)


func test_bounds_y_full_grid() -> void:
	var m: PackedByteArray = _full_mask(5, 11)
	var b: Vector2 = Formation.bounds_y(m, 5, 11, 16.0, 40.0, 16.0, 14.0, 5.0)
	# row 0 center = 40 + 7 = 47; top = 42
	# row 4 center = 40 + 4*14 + 7 = 103; bottom = 108
	assert_almost_eq(b.x, 42.0, 1e-6)
	assert_almost_eq(b.y, 108.0, 1e-6)


func test_bounds_empty_returns_neg_inf() -> void:
	var m: PackedByteArray = PackedByteArray()
	m.resize(55)  # all zeros
	var bx: Vector2 = Formation.bounds_x(m, 5, 11, 0.0, 0.0, 16.0, 14.0, 6.0)
	assert_eq(bx.x, -INF)


func test_live_count() -> void:
	assert_eq(Formation.live_count(_full_mask(5, 11)), 55)
	var m: PackedByteArray = _full_mask(5, 11)
	for i in range(10):
		m[i] = 0
	assert_eq(Formation.live_count(m), 45)


func test_step_ms_for_population_bounds() -> void:
	# Full population → step_ms_init.
	assert_eq(Formation.step_ms_for_population(55, 55, 800, 80), 800)
	# Single survivor → min_step_ms (1/55 lerp lands close to min).
	var ms: int = Formation.step_ms_for_population(1, 55, 800, 80)
	# t = 1/55 ≈ 0.018 → ms ≈ 80 + 0.018*(800-80) ≈ 93.
	assert_lt(ms, 100)
	# Zero alive → min_step_ms.
	assert_eq(Formation.step_ms_for_population(0, 55, 800, 80), 80)


func test_step_ms_monotonic() -> void:
	# Killing enemies one-by-one: step_ms strictly non-increasing.
	var prev: int = 100000
	for live in range(55, 0, -1):
		var ms: int = Formation.step_ms_for_population(live, 55, 800, 80)
		assert_true(ms <= prev, "step_ms should not increase when population shrinks (live=%d)" % live)
		prev = ms


func test_find_firing_column_skips_empty() -> void:
	# Mark only column 7 alive. Whatever seed we pass, find_firing_column
	# must land on 7 (it walks rightward).
	var m: PackedByteArray = PackedByteArray()
	m.resize(5 * 11)
	for r in range(5):
		m[r * 11 + 7] = 1
	for seed in range(20):
		assert_eq(Formation.find_firing_column(m, 5, 11, seed), 7)


func test_find_firing_column_no_alive() -> void:
	var m: PackedByteArray = PackedByteArray()
	m.resize(55)
	assert_eq(Formation.find_firing_column(m, 5, 11, 0), -1)


func test_bottom_row() -> void:
	var m: PackedByteArray = _full_mask(5, 11)
	# Full column → bottom is row 4.
	assert_eq(Formation.bottom_row(m, 5, 11, 3), 4)
	# Kill row 4 of col 3 → bottom is row 3.
	m[4 * 11 + 3] = 0
	assert_eq(Formation.bottom_row(m, 5, 11, 3), 3)
	# Kill all of col 3 → -1.
	for r in range(5):
		m[r * 11 + 3] = 0
	assert_eq(Formation.bottom_row(m, 5, 11, 3), -1)
