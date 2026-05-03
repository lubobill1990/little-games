extends GutTest
## bunker_grid.gd — get/clear/aabb_hit/snapshot.

const BunkerGrid := preload("res://scripts/invaders/core/bunker_grid.gd")


func _solid_pattern(w: int, h: int) -> PackedByteArray:
	var p: PackedByteArray = PackedByteArray()
	p.resize(w * h)
	for i in range(p.size()):
		p[i] = 1
	return p


func test_create_copies_pattern() -> void:
	var p: PackedByteArray = _solid_pattern(4, 3)
	var bg = BunkerGrid.create(4, 3, p)
	assert_eq(bg.w, 4)
	assert_eq(bg.h, 3)
	# Mutate source — shouldn't affect grid.
	p[0] = 0
	assert_eq(bg.get_cell(0, 0), 1)


func test_clear_cell_in_bounds() -> void:
	var bg = BunkerGrid.create(4, 3, _solid_pattern(4, 3))
	bg.clear_cell(2, 1)
	assert_eq(bg.get_cell(2, 1), 0)
	assert_eq(bg.get_cell(2, 0), 1)


func test_clear_cell_out_of_bounds_noop() -> void:
	var bg = BunkerGrid.create(4, 3, _solid_pattern(4, 3))
	bg.clear_cell(99, 99)
	bg.clear_cell(-1, 0)
	# Original cells intact.
	assert_eq(bg.get_cell(0, 0), 1)


func test_apply_stamp_clears_matching_cells() -> void:
	# Solid 5x5 grid; stamp = bottom-row 1's, anchor at center bottom.
	var bg = BunkerGrid.create(5, 5, _solid_pattern(5, 5))
	var stamp: PackedByteArray = PackedByteArray()
	stamp.resize(3 * 1)
	stamp[0] = 1; stamp[1] = 1; stamp[2] = 1
	# Anchor sx=1 (center) sy=0 (top of stamp). Apply at grid (2, 4).
	var cleared: int = bg.apply_stamp(stamp, 3, 1, 2, 4, 1, 0)
	assert_eq(cleared, 3)
	# Expect (1,4), (2,4), (3,4) cleared.
	assert_eq(bg.get_cell(1, 4), 0)
	assert_eq(bg.get_cell(2, 4), 0)
	assert_eq(bg.get_cell(3, 4), 0)
	# (0,4) and (4,4) untouched.
	assert_eq(bg.get_cell(0, 4), 1)
	assert_eq(bg.get_cell(4, 4), 1)


func test_apply_stamp_clips_out_of_bounds() -> void:
	var bg = BunkerGrid.create(3, 3, _solid_pattern(3, 3))
	# 5-wide stamp centered at col 0 → 2 cells go off the left edge.
	var stamp: PackedByteArray = PackedByteArray()
	stamp.resize(5)
	for i in range(5):
		stamp[i] = 1
	var cleared: int = bg.apply_stamp(stamp, 5, 1, 0, 0, 2, 0)
	# Only (0,0), (1,0), (2,0) actually exist → 3 cleared.
	assert_eq(cleared, 3)


func test_apply_stamp_already_empty_doesnt_count() -> void:
	var bg = BunkerGrid.create(3, 3, _solid_pattern(3, 3))
	bg.clear_cell(1, 1)
	var stamp: PackedByteArray = PackedByteArray()
	stamp.resize(1)
	stamp[0] = 1
	# Stamp the already-cleared cell.
	var cleared: int = bg.apply_stamp(stamp, 1, 1, 1, 1, 0, 0)
	assert_eq(cleared, 0)


func test_aabb_hit_finds_filled_cell() -> void:
	# 4x4 solid grid; cells 2x2; bunker origin at (10, 20).
	# AABB at (12, 22) with extents 1,1 → covers cells (1,1) area. Should hit.
	var bg = BunkerGrid.create(4, 4, _solid_pattern(4, 4))
	var out: Dictionary = {}
	var hit: bool = bg.aabb_hit(10.0, 20.0, 2.0, 2.0, 12.0, 22.0, 1.0, 1.0, out)
	assert_true(hit)
	# We expect the first filled cell scanned to be reported. Just verify
	# the (cx,cy) returned is in-range.
	assert_true(out.has("cx"))
	assert_true(int(out["cx"]) >= 0 and int(out["cx"]) < 4)


func test_aabb_hit_misses_when_all_empty() -> void:
	var bg = BunkerGrid.create(4, 4, _solid_pattern(4, 4))
	# Clear all cells in the area.
	for cx in range(4):
		for cy in range(4):
			bg.clear_cell(cx, cy)
	var out: Dictionary = {}
	assert_false(bg.aabb_hit(10.0, 20.0, 2.0, 2.0, 12.0, 22.0, 1.0, 1.0, out))


func test_aabb_hit_outside_grid_returns_false() -> void:
	var bg = BunkerGrid.create(4, 4, _solid_pattern(4, 4))
	var out: Dictionary = {}
	# AABB far away from bunker (origin 10,20; size 8x8) → completely off.
	assert_false(bg.aabb_hit(10.0, 20.0, 2.0, 2.0, 100.0, 100.0, 1.0, 1.0, out))


func test_snapshot_round_trip() -> void:
	var bg = BunkerGrid.create(3, 3, _solid_pattern(3, 3))
	bg.clear_cell(1, 1)
	bg.clear_cell(0, 2)
	var snap: PackedByteArray = bg.snapshot_cells()
	var bg2 = BunkerGrid.from_snapshot(3, 3, snap)
	assert_eq(bg2.w, 3)
	assert_eq(bg2.h, 3)
	assert_eq(bg2.get_cell(1, 1), 0)
	assert_eq(bg2.get_cell(0, 2), 0)
	assert_eq(bg2.get_cell(0, 0), 1)
	# Mutate original — snapshot copy shouldn't aliase.
	bg.clear_cell(2, 2)
	assert_eq(bg2.get_cell(2, 2), 1)
