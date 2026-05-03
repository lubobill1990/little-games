extends GutTest
## tank_entity.gd — rail-snap + tile/tank movement helpers.
## Movement integration with TankGameState lives in test_state_lifecycle.gd.

const TankEntity := preload("res://scripts/tank/core/tank_entity.gd")
const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")


func _empty_grid() -> TileGrid:
	var rows: PackedStringArray = PackedStringArray()
	for r in range(13):
		rows.append(".............")
	return TileGrid.from_rows(rows)


func _grid_with_brick_at(c: int, r: int) -> TileGrid:
	var rows: PackedStringArray = PackedStringArray()
	for ri in range(13):
		var row: String = ""
		for ci in range(13):
			row += ("B" if ci == c and ri == r else ".")
		# Need an H somewhere for from_rows assertions to NOT fire — but
		# from_rows doesn't actually require H, that's tank_level.parse_tiles.
		# Leave row as-is.
		rows.append(row)
	return TileGrid.from_rows(rows)


func _player_tank(cfg: TankConfig, sx: int, sy: int) -> Dictionary:
	return TankEntity.make_player(0, sx, sy, cfg)


# --- make_player ---

func test_make_player_centers_on_2x2_spawn_tile() -> void:
	var cfg: TankConfig = TankConfig.new()
	# Spawn at tile (3, 4) → center is (3*16 + 16, 4*16 + 16) = (64, 80).
	var t: Dictionary = TankEntity.make_player(0, 3, 4, cfg)
	assert_eq(t["x"], 64)
	assert_eq(t["y"], 80)
	assert_eq(t["facing"], TileGrid.DIR_N)
	assert_false(t["moving"])
	assert_true(t["alive"])
	assert_eq(t["player_idx"], 0)
	assert_eq(t["kind"], "player")
	assert_eq(t["owner"], 1)


func test_half_extents_default() -> void:
	var cfg: TankConfig = TankConfig.new()
	var hxhy: Array = TankEntity.half_extents(cfg)
	assert_eq(hxhy[0], 16)  # 2 tiles * 16 sub-px / 2
	assert_eq(hxhy[1], 16)


# --- tiles_under_tank ---

func test_tiles_under_tank_aligned_2x2() -> void:
	var cfg: TankConfig = TankConfig.new()
	# Tank centered at (16, 16) with half-extents (16, 16) covers
	# x ∈ [0, 32), y ∈ [0, 32) → tiles (0,0), (1,0), (0,1), (1,1).
	var tiles: Array = TankEntity.tiles_under_tank(16, 16, cfg)
	assert_eq(tiles.size(), 4)
	assert_true(tiles.has([0, 0]))
	assert_true(tiles.has([1, 0]))
	assert_true(tiles.has([0, 1]))
	assert_true(tiles.has([1, 1]))


func test_tiles_under_tank_off_rail_spans_3_columns() -> void:
	var cfg: TankConfig = TankConfig.new()
	# Center (20, 16) — shifted 4 sub-px right of (16,16). Half-extent 16.
	# x ∈ [4, 36) → tiles 0, 1, 2 in X. Two in Y → 6 tiles total.
	var tiles: Array = TankEntity.tiles_under_tank(20, 16, cfg)
	assert_eq(tiles.size(), 6)


# --- snap_to_rail ---

func test_snap_to_rail_no_op_when_axis_unchanged() -> void:
	var cfg: TankConfig = TankConfig.new()
	var t: Dictionary = _player_tank(cfg, 3, 3)
	# Pretend the tank's x is off-rail (not a multiple of 4).
	t["x"] = 65  # not a multiple of 4
	t["facing"] = TileGrid.DIR_N
	# Re-issuing N → N is not perpendicular; should NOT snap.
	var got: int = TankEntity.snap_to_rail(t, TileGrid.DIR_N, cfg)
	assert_eq(got, 65)
	assert_eq(t["x"], 65, "x untouched on same-axis intent")


func test_snap_to_rail_snaps_x_when_flipping_to_horizontal() -> void:
	var cfg: TankConfig = TankConfig.new()
	var t: Dictionary = _player_tank(cfg, 3, 3)
	t["facing"] = TileGrid.DIR_N  # vertical
	t["y"] = 65                    # off-rail Y
	# Flip to E (horizontal) → snap Y to nearest 4 = 64.
	var got: int = TankEntity.snap_to_rail(t, TileGrid.DIR_E, cfg)
	assert_eq(got, 64)
	assert_eq(t["y"], 64)


func test_snap_to_rail_snaps_y_when_flipping_to_vertical() -> void:
	var cfg: TankConfig = TankConfig.new()
	var t: Dictionary = _player_tank(cfg, 3, 3)
	t["facing"] = TileGrid.DIR_E  # horizontal
	t["x"] = 67                    # off-rail X; nearest 4 is 68
	var got: int = TankEntity.snap_to_rail(t, TileGrid.DIR_S, cfg)
	assert_eq(got, 68)
	assert_eq(t["x"], 68)


func test_snap_to_rail_round_half_up() -> void:
	var cfg: TankConfig = TankConfig.new()
	# rail_snap_sub == 4. Halfway value 66 should round up to 68.
	var t: Dictionary = _player_tank(cfg, 3, 3)
	t["facing"] = TileGrid.DIR_E
	t["x"] = 66
	var got: int = TankEntity.snap_to_rail(t, TileGrid.DIR_S, cfg)
	assert_eq(got, 68)


# --- try_step ---

func test_try_step_advances_in_facing_direction() -> void:
	var cfg: TankConfig = TankConfig.new()
	var grid: TileGrid = _empty_grid()
	# Tank at center (32, 32), facing E, moving=true.
	var t: Dictionary = _player_tank(cfg, 1, 1)
	t["facing"] = TileGrid.DIR_E
	t["moving"] = true
	var moved: bool = TankEntity.try_step(t, 1, grid, cfg, [])
	assert_true(moved)
	assert_eq(t["x"], 33)
	assert_eq(t["y"], 32)


func test_try_step_no_op_when_not_moving() -> void:
	var cfg: TankConfig = TankConfig.new()
	var grid: TileGrid = _empty_grid()
	var t: Dictionary = _player_tank(cfg, 1, 1)
	t["facing"] = TileGrid.DIR_E
	t["moving"] = false
	var moved: bool = TankEntity.try_step(t, 1, grid, cfg, [])
	assert_false(moved)
	assert_eq(t["x"], 32)


func test_try_step_blocked_by_brick() -> void:
	var cfg: TankConfig = TankConfig.new()
	# Tank at (1,1) tile-center. Place a brick at (3, 1) — tank's right
	# edge at x=48 would touch tile col 3 (which spans 48-63). Move E
	# repeatedly until it would enter col 3.
	var grid: TileGrid = _grid_with_brick_at(3, 1)
	var t: Dictionary = _player_tank(cfg, 1, 1)
	t["facing"] = TileGrid.DIR_E
	t["moving"] = true
	# x starts at 32; right edge at 48 (col 3 boundary). One step E moves
	# x to 33 → right edge at 49 → spills into brick at col 3 → blocked.
	var moved: bool = TankEntity.try_step(t, 1, grid, cfg, [])
	assert_false(moved)
	assert_eq(t["x"], 32, "blocked, position unchanged")


func test_try_step_blocked_by_world_edge() -> void:
	var cfg: TankConfig = TankConfig.new()
	var grid: TileGrid = _empty_grid()
	# Tank centered at (16, 16) facing W; a step W puts left edge at -1
	# → tile col -1 → off-grid → reads as STEEL → blocked.
	var t: Dictionary = _player_tank(cfg, 0, 0)
	t["facing"] = TileGrid.DIR_W
	t["moving"] = true
	var moved: bool = TankEntity.try_step(t, 1, grid, cfg, [])
	assert_false(moved)
	assert_eq(t["x"], 16)


func test_try_step_blocked_by_other_tank() -> void:
	var cfg: TankConfig = TankConfig.new()
	var grid: TileGrid = _empty_grid()
	var a: Dictionary = _player_tank(cfg, 1, 1)  # center (32,32)
	a["facing"] = TileGrid.DIR_E
	a["moving"] = true
	# Place another tank one sub-px to the east (so any step would overlap).
	var b: Dictionary = _player_tank(cfg, 1, 1)
	b["x"] = 64  # touching at edge (a right edge=48, b left edge=48 → touch, not overlap)
	# After A steps east by 1: A right edge=49, B left edge=48 → overlap.
	var moved: bool = TankEntity.try_step(a, 1, grid, cfg, [b])
	assert_false(moved, "must refuse step that would overlap teammate")
	assert_eq(a["x"], 32)


func test_try_step_passes_through_grass_and_ice() -> void:
	var cfg: TankConfig = TankConfig.new()
	var rows: PackedStringArray = PackedStringArray()
	for r in range(13):
		rows.append(".....GGGI....")  # row of grass + ice in middle
	var grid: TileGrid = TileGrid.from_rows(rows)
	var t: Dictionary = _player_tank(cfg, 5, 5)
	t["facing"] = TileGrid.DIR_E
	t["moving"] = true
	# Should be able to step east freely in this row.
	for i in range(4):
		var moved: bool = TankEntity.try_step(t, 1, grid, cfg, [])
		assert_true(moved, "iter %d" % i)


func test_try_step_blocked_by_water_without_ship() -> void:
	var cfg: TankConfig = TankConfig.new()
	var rows: PackedStringArray = PackedStringArray()
	for r in range(13):
		rows.append("....WWW......")  # water at cols 4..6
	var grid: TileGrid = TileGrid.from_rows(rows)
	# Tank at (1, 1) → center (32, 32). Step E until blocked.
	var t: Dictionary = _player_tank(cfg, 1, 1)
	t["facing"] = TileGrid.DIR_E
	t["moving"] = true
	# Right edge at 48 (col 3 boundary). One step → right edge 49 → enters
	# col 3 (still empty) → succeeds. Continue until right edge would enter
	# col 4 (water) at x=49 → wait, col 4 starts at x=64. Need 16 more
	# steps to reach blockage. Just step many times and assert eventually
	# blocked while x < some bound.
	var blocked_at: int = -1
	for i in range(40):
		var moved: bool = TankEntity.try_step(t, 1, grid, cfg, [])
		if not moved:
			blocked_at = t["x"]
			break
	assert_ne(blocked_at, -1, "tank should hit water and stop")
	# Right edge at blocked_at + 16 should be inside col 4 (>= 64).
	assert_true((blocked_at + 16) >= 64, "blocked at x=%d (right edge %d)" % [blocked_at, blocked_at + 16])


func test_try_step_passes_water_with_ship() -> void:
	var cfg: TankConfig = TankConfig.new()
	var rows: PackedStringArray = PackedStringArray()
	for r in range(13):
		rows.append("....WWW......")  # water at cols 4..6
	var grid: TileGrid = TileGrid.from_rows(rows)
	var t: Dictionary = _player_tank(cfg, 1, 1)
	t["facing"] = TileGrid.DIR_E
	t["moving"] = true
	t["has_ship"] = true
	# With ship, tank can cross water. Step until well past col 6.
	var passes: int = 0
	for i in range(80):
		if TankEntity.try_step(t, 1, grid, cfg, []):
			passes += 1
	assert_gt(passes, 60, "ship should let tank cross water unhindered")
