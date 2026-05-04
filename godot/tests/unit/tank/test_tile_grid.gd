extends GutTest
## tile_grid.gd — tile classification, passability, half-brick erosion,
## steel destruction, snapshot round-trip.

const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")


func _solid_brick_grid() -> TileGrid:
	var rows: PackedStringArray = PackedStringArray()
	for r in range(13):
		var row: String = ""
		for c in range(13):
			row += "B"
		rows.append(row)
	return TileGrid.from_rows(rows)


func _empty_grid() -> TileGrid:
	var rows: PackedStringArray = PackedStringArray()
	for r in range(13):
		rows.append(".............")
	return TileGrid.from_rows(rows)


# --- construction + accessors ---

func test_from_rows_classifies_each_tile() -> void:
	var rows: PackedStringArray = PackedStringArray([
		".BSWGI.......",
		"H............",
		"P.E..........",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
	])
	var g: TileGrid = TileGrid.from_rows(rows)
	assert_eq(g.get_tile(0, 0), TileGrid.TILE_EMPTY)
	assert_eq(g.get_tile(1, 0), TileGrid.TILE_BRICK)
	assert_eq(g.get_tile(2, 0), TileGrid.TILE_STEEL)
	assert_eq(g.get_tile(3, 0), TileGrid.TILE_WATER)
	assert_eq(g.get_tile(4, 0), TileGrid.TILE_GRASS)
	assert_eq(g.get_tile(5, 0), TileGrid.TILE_ICE)
	assert_eq(g.get_tile(0, 1), TileGrid.TILE_BASE)
	# P / E spawn markers are stored as TILE_EMPTY (level loader keeps coords).
	assert_eq(g.get_tile(0, 2), TileGrid.TILE_EMPTY)
	assert_eq(g.get_tile(2, 2), TileGrid.TILE_EMPTY)


func test_off_grid_reads_as_steel() -> void:
	var g: TileGrid = _empty_grid()
	# Off-grid acts as solid steel for collision so tank/bullet logic
	# treats world bounds uniformly.
	assert_eq(g.get_tile(-1, 0), TileGrid.TILE_STEEL)
	assert_eq(g.get_tile(13, 0), TileGrid.TILE_STEEL)
	assert_eq(g.get_tile(0, -1), TileGrid.TILE_STEEL)
	assert_eq(g.get_tile(0, 13), TileGrid.TILE_STEEL)


func test_set_tile_out_of_bounds_noop() -> void:
	var g: TileGrid = _empty_grid()
	g.set_tile(99, 99, TileGrid.TILE_BRICK)
	# Internal grid still all empty.
	assert_eq(g.get_tile(0, 0), TileGrid.TILE_EMPTY)


# --- passability ---

func test_tank_passability_no_ship() -> void:
	var rows: PackedStringArray = PackedStringArray([
		"BSWGI.H......",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
	])
	var g: TileGrid = TileGrid.from_rows(rows)
	assert_false(g.tile_passable_for_tank(0, 0, false), "brick blocks tank")
	assert_false(g.tile_passable_for_tank(1, 0, false), "steel blocks tank")
	assert_false(g.tile_passable_for_tank(2, 0, false), "water blocks tank w/o ship")
	assert_true(g.tile_passable_for_tank(3, 0, false), "grass passable")
	assert_true(g.tile_passable_for_tank(4, 0, false), "ice passable")
	assert_true(g.tile_passable_for_tank(5, 0, false), "empty passable")
	assert_false(g.tile_passable_for_tank(6, 0, false), "base blocks tank")


func test_tank_passability_with_ship() -> void:
	var g: TileGrid = TileGrid.from_rows(PackedStringArray([
		"BSWG.........",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
	]))
	# Brick / steel still block; water now passes.
	assert_false(g.tile_passable_for_tank(0, 0, true))
	assert_false(g.tile_passable_for_tank(1, 0, true))
	assert_true(g.tile_passable_for_tank(2, 0, true), "water passable with ship")
	assert_true(g.tile_passable_for_tank(3, 0, true))


func test_bullet_passability() -> void:
	var g: TileGrid = TileGrid.from_rows(PackedStringArray([
		"BSWGI.H......",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
	]))
	assert_false(g.tile_passable_for_bullet(0, 0), "brick blocks bullet")
	assert_false(g.tile_passable_for_bullet(1, 0), "steel blocks bullet")
	assert_true(g.tile_passable_for_bullet(2, 0), "water passes bullet")
	assert_true(g.tile_passable_for_bullet(3, 0), "grass passes bullet")
	assert_true(g.tile_passable_for_bullet(4, 0), "ice passes bullet")
	assert_false(g.tile_passable_for_bullet(6, 0), "base blocks bullet")


func test_destroyed_brick_passable_for_tank_and_bullet() -> void:
	var g: TileGrid = _solid_brick_grid()
	# Hit twice from north → destroyed.
	g.erode_brick(5, 5, TileGrid.DIR_N)
	g.erode_brick(5, 5, TileGrid.DIR_N)
	assert_eq(g.get_brick(5, 5), TileGrid.BRICK_DESTROYED)
	assert_true(g.tile_passable_for_tank(5, 5, false))
	assert_true(g.tile_passable_for_bullet(5, 5))


# --- erosion ---

func test_erode_brick_north_eats_bottom_first() -> void:
	var g: TileGrid = _solid_brick_grid()
	var destroyed: bool = g.erode_brick(3, 3, TileGrid.DIR_N)
	assert_false(destroyed, "first hit doesn't destroy")
	assert_eq(g.get_brick(3, 3), TileGrid.BRICK_BOTTOM_GONE)


func test_erode_brick_south_eats_top_first() -> void:
	var g: TileGrid = _solid_brick_grid()
	g.erode_brick(3, 3, TileGrid.DIR_S)
	assert_eq(g.get_brick(3, 3), TileGrid.BRICK_TOP_GONE)


func test_erode_brick_east_eats_left_first() -> void:
	var g: TileGrid = _solid_brick_grid()
	g.erode_brick(3, 3, TileGrid.DIR_E)
	assert_eq(g.get_brick(3, 3), TileGrid.BRICK_LEFT_GONE)


func test_erode_brick_west_eats_right_first() -> void:
	var g: TileGrid = _solid_brick_grid()
	g.erode_brick(3, 3, TileGrid.DIR_W)
	assert_eq(g.get_brick(3, 3), TileGrid.BRICK_RIGHT_GONE)


func test_erode_brick_second_hit_destroys() -> void:
	var g: TileGrid = _solid_brick_grid()
	g.erode_brick(3, 3, TileGrid.DIR_N)
	var destroyed: bool = g.erode_brick(3, 3, TileGrid.DIR_S)
	assert_true(destroyed, "second hit destroys regardless of direction")
	assert_eq(g.get_brick(3, 3), TileGrid.BRICK_DESTROYED)
	# Underlying tile is now empty.
	assert_eq(g.get_tile(3, 3), TileGrid.TILE_EMPTY)


func test_erode_brick_destroyed_no_op() -> void:
	var g: TileGrid = _solid_brick_grid()
	g.erode_brick(3, 3, TileGrid.DIR_N)
	g.erode_brick(3, 3, TileGrid.DIR_N)
	assert_eq(g.get_brick(3, 3), TileGrid.BRICK_DESTROYED)
	# Subsequent hit is a no-op (returns false, no state change).
	var destroyed: bool = g.erode_brick(3, 3, TileGrid.DIR_N)
	assert_false(destroyed)
	assert_eq(g.get_brick(3, 3), TileGrid.BRICK_DESTROYED)


func test_erode_brick_off_grid_no_op() -> void:
	var g: TileGrid = _solid_brick_grid()
	var destroyed: bool = g.erode_brick(99, 99, TileGrid.DIR_N)
	assert_false(destroyed)


func test_erode_brick_on_non_brick_no_op() -> void:
	var rows: PackedStringArray = PackedStringArray()
	for r in range(13):
		rows.append(".............")
	var g: TileGrid = TileGrid.from_rows(rows)
	var destroyed: bool = g.erode_brick(5, 5, TileGrid.DIR_N)
	assert_false(destroyed)


# --- steel destruction (star ≥ 2) ---

func test_break_steel_destroys_full_tile() -> void:
	var g: TileGrid = TileGrid.from_rows(PackedStringArray([
		"SS...........",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
	]))
	var ok: bool = g.break_steel(0, 0)
	assert_true(ok)
	assert_eq(g.get_tile(0, 0), TileGrid.TILE_EMPTY)
	# Other steel still intact.
	assert_eq(g.get_tile(1, 0), TileGrid.TILE_STEEL)


func test_break_steel_on_brick_no_op() -> void:
	var g: TileGrid = _solid_brick_grid()
	assert_false(g.break_steel(5, 5))
	assert_eq(g.get_tile(5, 5), TileGrid.TILE_BRICK)


# --- snapshot round-trip ---

func test_snapshot_round_trip_preserves_tiles_and_bricks() -> void:
	var g: TileGrid = _solid_brick_grid()
	g.erode_brick(3, 3, TileGrid.DIR_N)
	g.erode_brick(7, 7, TileGrid.DIR_S)
	g.erode_brick(7, 7, TileGrid.DIR_E)  # destroys
	var snap_t: PackedByteArray = g.snapshot_tiles()
	var snap_b: PackedByteArray = g.snapshot_bricks()
	# Mutate the original; snapshot should be detached.
	g.set_tile(0, 0, TileGrid.TILE_STEEL)
	g.set_brick(3, 3, TileGrid.BRICK_DESTROYED)
	# Restore from snapshot.
	var g2: TileGrid = TileGrid.from_snapshot(snap_t, snap_b)
	assert_eq(g2.get_tile(0, 0), TileGrid.TILE_BRICK, "restored tile from snapshot")
	assert_eq(g2.get_brick(3, 3), TileGrid.BRICK_BOTTOM_GONE, "restored brick state")
	assert_eq(g2.get_brick(7, 7), TileGrid.BRICK_DESTROYED)
	assert_eq(g2.get_tile(7, 7), TileGrid.TILE_EMPTY)


func test_snapshot_byte_arrays_are_copies() -> void:
	var g: TileGrid = _solid_brick_grid()
	var snap_t: PackedByteArray = g.snapshot_tiles()
	# Mutate the snapshot; original should be unaffected.
	snap_t[0] = TileGrid.TILE_STEEL
	assert_eq(g.get_tile(0, 0), TileGrid.TILE_BRICK, "snapshot is a copy")
