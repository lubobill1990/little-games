extends GutTest
## bullet.gd + tank_state bullet phase — terrain interactions.
##
## Covers: motion, out-of-world consume, brick erosion (half + destroy on
## second hit), steel block (star < 2) vs steel break (star ≥ 2), water /
## grass / ice pass-through, base destruction.

const Bullet := preload("res://scripts/tank/core/bullet.gd")
const TankState := preload("res://scripts/tank/core/tank_state.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")
const TankEntity := preload("res://scripts/tank/core/tank_entity.gd")
const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")


# --- fixtures ---

func _level_with(rows_in: PackedStringArray) -> String:
	# parse_tiles requires exactly 13 13-char rows + at least one H + at
	# least one P + at least one E. Caller passes `rows_in` and we splat
	# them into a clean 13×13 base, then guarantee H/P/E presence.
	var rows: PackedStringArray = PackedStringArray()
	for r in range(13):
		if r < rows_in.size():
			rows.append(rows_in[r])
		else:
			rows.append(".............")
	# Mandatory markers placed off to the side so they don't interfere.
	# Force base at (6, 12), P at (4, 11), E at (0, 0).
	rows[12] = _put_at(rows[12], 6, "H")
	rows[11] = _put_at(rows[11], 4, "P")
	rows[0] = _put_at(rows[0], 0, "E")
	var out: String = ""
	for r in rows:
		out += r + "\n"
	return out


func _put_at(row: String, col: int, ch: String) -> String:
	return row.substr(0, col) + ch + row.substr(col + 1)


func _basic_roster() -> String:
	# 20 entries, 3 +bonus markers — minimum tank_level requirements.
	var out: String = ""
	for i in range(20):
		var bonus: String = " +bonus" if i < 3 else ""
		out += "basic" + bonus + "\n"
	return out


func _spawn_state(rows_in: PackedStringArray) -> TankState:
	var s: TankState = TankState.create(42, _level_with(rows_in), _basic_roster(), 1, TankConfig.new())
	assert_not_null(s, "state should build for fixture")
	s.set_last_tick(0)
	return s


# --- pure motion ---

func test_advance_moves_in_dir() -> void:
	var b: Dictionary = {
		"owner_kind": "player", "owner_idx": 0,
		"x": 50, "y": 60, "dir": TileGrid.DIR_N, "speed_sub": 4,
		"star": 0, "alive": true,
	}
	Bullet.advance(b)
	assert_eq(b["x"], 50)
	assert_eq(b["y"], 56)
	b["dir"] = TileGrid.DIR_E
	Bullet.advance(b)
	assert_eq(b["x"], 54)
	assert_eq(b["y"], 56)


func test_advance_skips_dead_bullets() -> void:
	var b: Dictionary = {
		"owner_kind": "player", "owner_idx": 0,
		"x": 50, "y": 60, "dir": TileGrid.DIR_S, "speed_sub": 4,
		"star": 0, "alive": false,
	}
	Bullet.advance(b)
	assert_eq(b["y"], 60, "dead bullet must not move")


func test_out_of_world_when_past_edge() -> void:
	var cfg: TankConfig = TankConfig.new()
	# World runs 0..208. AABB half-extent is 2.
	var b: Dictionary = {
		"owner_kind": "player", "owner_idx": 0,
		"x": 1, "y": 100, "dir": TileGrid.DIR_W, "speed_sub": 4,
		"star": 0, "alive": true,
	}
	# Center at 1, half-w=2 → left edge at -1 → out.
	assert_true(Bullet.out_of_world(b, cfg))
	b["x"] = 100
	assert_false(Bullet.out_of_world(b, cfg))


func test_spawn_from_tank_offsets_to_muzzle() -> void:
	var cfg: TankConfig = TankConfig.new()
	# Tank at (32, 32) facing N. Muzzle should sit above tank: y = 32 - 16 - 2 = 14.
	var t: Dictionary = TankEntity.make_player(0, 1, 1, cfg)
	t["facing"] = TileGrid.DIR_N
	var b: Dictionary = Bullet.spawn_from_tank(t, cfg, "player", 0, 4, 0)
	assert_eq(b["x"], 32)
	assert_eq(b["y"], 14)
	assert_eq(b["dir"], TileGrid.DIR_N)
	assert_true(b["alive"])
	assert_eq(b["owner_kind"], "player")
	assert_eq(b["owner_idx"], 0)


# --- vs-tile via tank_state.tick ---

func test_bullet_consumed_at_world_edge() -> void:
	# Player at (4, 11) → center (4*16+16, 11*16+16) = (80, 192).
	# Fire west. Bullet should travel until x - 2 < 0 then disappear.
	var s: TankState = _spawn_state(PackedStringArray())
	# Aim P1 west by setting facing manually before fire.
	s.players[0]["facing"] = TileGrid.DIR_W
	assert_true(s.request_fire(0))
	assert_eq(s.bullets.size(), 1)
	# After enough sub-steps, bullet should be pruned. World width 208 → ~20 ticks at speed 4.
	var t: int = 16
	for i in range(40):
		s.tick(t)
		t += 16
		if s.bullets.is_empty():
			break
	assert_eq(s.bullets.size(), 0, "bullet must be consumed at world edge")


func test_bullet_erodes_brick_half_then_destroys() -> void:
	# Place a brick at (4, 9) and fire from P (4, 11) facing N.
	# Bullet will travel up the column and hit the brick.
	var rows: PackedStringArray = PackedStringArray()
	for r in range(13):
		var row: String = "............."
		if r == 9:
			row = _put_at(row, 4, "B")
		rows.append(row)
	var s: TankState = _spawn_state(rows)
	s.players[0]["facing"] = TileGrid.DIR_N
	assert_true(s.request_fire(0))
	# Tick until first hit.
	var t: int = 16
	for i in range(80):
		s.tick(t); t += 16
		if s.bullets.is_empty():
			break
	# After consume, brick at (4,9) must be in BOTTOM_GONE state (north-traveling
	# bullet eats the bottom half).
	assert_eq(s.grid.get_brick(4, 9), TileGrid.BRICK_BOTTOM_GONE)
	assert_eq(s.grid.get_tile(4, 9), TileGrid.TILE_BRICK, "still brick after one hit")
	# Fire again; the second hit destroys.
	s.release_fire(0)
	# Wait for cooldown.
	t += 200
	s.set_last_tick(t)
	assert_true(s.request_fire(0))
	for i in range(80):
		s.tick(t); t += 16
		if s.bullets.is_empty():
			break
	assert_eq(s.grid.get_brick(4, 9), TileGrid.BRICK_DESTROYED)
	assert_eq(s.grid.get_tile(4, 9), TileGrid.TILE_EMPTY)


func test_bullet_blocked_by_steel_when_star_low() -> void:
	var rows: PackedStringArray = PackedStringArray()
	for r in range(13):
		var row: String = "............."
		if r == 9:
			row = _put_at(row, 4, "S")
		rows.append(row)
	var s: TankState = _spawn_state(rows)
	s.players[0]["facing"] = TileGrid.DIR_N
	# star=0 → bullet bounces off steel (consumed, no break).
	assert_true(s.request_fire(0))
	var t: int = 16
	for i in range(80):
		s.tick(t); t += 16
		if s.bullets.is_empty():
			break
	assert_eq(s.grid.get_tile(4, 9), TileGrid.TILE_STEEL, "star 0 must not break steel")


func test_star2_bullet_breaks_steel() -> void:
	var rows: PackedStringArray = PackedStringArray()
	for r in range(13):
		var row: String = "............."
		if r == 9:
			row = _put_at(row, 4, "S")
		rows.append(row)
	var s: TankState = _spawn_state(rows)
	s.players[0]["star"] = 2
	s.players[0]["facing"] = TileGrid.DIR_N
	assert_true(s.request_fire(0))
	var t: int = 16
	for i in range(80):
		s.tick(t); t += 16
		if s.bullets.is_empty():
			break
	assert_eq(s.grid.get_tile(4, 9), TileGrid.TILE_EMPTY, "star 2 must clear steel")


func test_bullet_passes_through_water_grass_ice() -> void:
	# Fill row 5 with G G G W W I — bullet flying east through it shouldn't
	# stop until it leaves the world.
	var rows: PackedStringArray = PackedStringArray()
	for r in range(13):
		var row: String = "............."
		if r == 6:
			row = "..GGGWWII...."
		rows.append(row)
	var s: TankState = _spawn_state(rows)
	# Move P to row 6 manually so we can fire east.
	s.players[0]["x"] = 16
	s.players[0]["y"] = 6 * 16 + 8  # center on row 6
	s.players[0]["facing"] = TileGrid.DIR_E
	assert_true(s.request_fire(0))
	var t: int = 16
	for i in range(80):
		s.tick(t); t += 16
		if s.bullets.is_empty():
			break
	assert_eq(s.bullets.size(), 0, "bullet must traverse soft tiles + leave world")


func test_bullet_destroys_base() -> void:
	# Default fixture puts H at (6, 12). Fire from P (4, 11), but redirect
	# manually: aim east toward base by relocating P to (5, 12 ish).
	var s: TankState = _spawn_state(PackedStringArray())
	# Reposition P1 just west of base, on the same row.
	s.players[0]["x"] = 4 * 16 + 16  # center at col 5 boundary (~ x=80)
	s.players[0]["y"] = 12 * 16 + 8  # center on row 12
	s.players[0]["facing"] = TileGrid.DIR_E
	assert_true(s.request_fire(0))
	var t: int = 16
	for i in range(80):
		s.tick(t); t += 16
		if s.bullets.is_empty():
			break
	assert_eq(s.grid.get_tile(6, 12), TileGrid.TILE_EMPTY, "base destroyed")


# --- request_fire latch + cap ---

func test_max_one_player_bullet_when_star_low() -> void:
	var s: TankState = _spawn_state(PackedStringArray())
	s.players[0]["facing"] = TileGrid.DIR_N
	assert_true(s.request_fire(0))
	# Same call without release: latched → false.
	assert_false(s.request_fire(0))
	s.release_fire(0)
	# Cooldown still holds.
	assert_false(s.request_fire(0))
	# Skip cooldown by advancing time past fire_cooldown_ms.
	s.set_last_tick(s.now_ms + 250)
	# But the existing bullet still in flight → cap hits → false.
	assert_false(s.request_fire(0), "max-bullets cap should reject second shot")


func test_two_player_bullets_when_star3() -> void:
	var s: TankState = _spawn_state(PackedStringArray())
	s.players[0]["star"] = 3
	s.players[0]["facing"] = TileGrid.DIR_N
	assert_true(s.request_fire(0))
	s.release_fire(0)
	s.set_last_tick(s.now_ms + 250)
	assert_true(s.request_fire(0), "star 3 allows 2 bullets in flight")
	s.release_fire(0)
	s.set_last_tick(s.now_ms + 250)
	assert_false(s.request_fire(0), "third bullet still rejected at star 3")
