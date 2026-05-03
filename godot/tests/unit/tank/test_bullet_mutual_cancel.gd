extends GutTest
## tank_state bullet phase — mutual cancel + within-sub-step ordering.
##
## Acceptance #5: when a player and enemy bullet AABB overlap on the same
## sub-step, both are removed before any other phase.
## Acceptance #6: resolution order is bullet-vs-bullet → bullet-vs-tank →
## bullet-vs-tile → bullet-vs-base; iteration in (owner_kind, owner_idx,
## bullet_idx).

const Bullet := preload("res://scripts/tank/core/bullet.gd")
const TankState := preload("res://scripts/tank/core/tank_state.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")
const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")


func _empty_level() -> String:
	# 13×13 empty + mandatory markers (H, P, E).
	var rows: PackedStringArray = PackedStringArray()
	for r in range(13):
		var row: String = "............."
		if r == 0:
			row = "E............"
		elif r == 11:
			row = "....P........"
		elif r == 12:
			row = "......H......"
		rows.append(row)
	var out: String = ""
	for r in rows:
		out += r + "\n"
	return out


func _basic_roster() -> String:
	var out: String = ""
	for i in range(20):
		var bonus: String = " +bonus" if i < 3 else ""
		out += "basic" + bonus + "\n"
	return out


func _state() -> TankState:
	var s: TankState = TankState.create(42, _empty_level(), _basic_roster(), 1, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	return s


# --- mutual cancel ---

func test_player_and_enemy_bullets_cancel_when_overlapping() -> void:
	var s: TankState = _state()
	# Inject one player bullet and one enemy bullet at the same coords —
	# AABBs overlap → both consumed on next sub-step before any other phase.
	s.bullets.append({
		"owner_kind": "player", "owner_idx": 0,
		"x": 100, "y": 100, "dir": TileGrid.DIR_E, "speed_sub": 0,
		"star": 0, "alive": true,
	})
	s.bullets.append({
		"owner_kind": "enemy", "owner_idx": 0,
		"x": 100, "y": 100, "dir": TileGrid.DIR_W, "speed_sub": 0,
		"star": 0, "alive": true,
	})
	# Tick exactly one sub-step.
	s.tick(16)
	assert_eq(s.bullets.size(), 0, "both bullets must be consumed")


func test_two_player_bullets_do_not_cancel() -> void:
	var s: TankState = _state()
	s.bullets.append({
		"owner_kind": "player", "owner_idx": 0,
		"x": 100, "y": 100, "dir": TileGrid.DIR_E, "speed_sub": 0,
		"star": 0, "alive": true,
	})
	s.bullets.append({
		"owner_kind": "player", "owner_idx": 0,
		"x": 100, "y": 100, "dir": TileGrid.DIR_W, "speed_sub": 0,
		"star": 0, "alive": true,
	})
	s.tick(16)
	assert_eq(s.bullets.size(), 2, "same-owner bullets must NOT cancel")


func test_two_enemy_bullets_do_not_cancel() -> void:
	var s: TankState = _state()
	s.bullets.append({
		"owner_kind": "enemy", "owner_idx": 0,
		"x": 100, "y": 100, "dir": TileGrid.DIR_E, "speed_sub": 0,
		"star": 0, "alive": true,
	})
	s.bullets.append({
		"owner_kind": "enemy", "owner_idx": 1,
		"x": 100, "y": 100, "dir": TileGrid.DIR_W, "speed_sub": 0,
		"star": 0, "alive": true,
	})
	s.tick(16)
	assert_eq(s.bullets.size(), 2, "enemy↔enemy must not cancel")


func test_cancel_preempts_brick_erosion() -> void:
	# Both bullets sitting on a brick tile: mutual cancel happens BEFORE
	# bullet-vs-tile, so the brick stays intact.
	var rows: PackedStringArray = PackedStringArray()
	for r in range(13):
		var row: String = "............."
		if r == 0:
			row = "E............"
		elif r == 6:
			row = ".....B......."  # brick at (5, 6)
		elif r == 11:
			row = "....P........"
		elif r == 12:
			row = "......H......"
		rows.append(row)
	var lvl: String = ""
	for r in rows:
		lvl += r + "\n"
	var s: TankState = TankState.create(42, lvl, _basic_roster(), 1, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	# Place both bullets centered on the brick (col 5 = x ∈ [80, 96), so center 88).
	s.bullets.append({
		"owner_kind": "player", "owner_idx": 0,
		"x": 88, "y": 6 * 16 + 8, "dir": TileGrid.DIR_N, "speed_sub": 0,
		"star": 0, "alive": true,
	})
	s.bullets.append({
		"owner_kind": "enemy", "owner_idx": 0,
		"x": 88, "y": 6 * 16 + 8, "dir": TileGrid.DIR_S, "speed_sub": 0,
		"star": 0, "alive": true,
	})
	s.tick(16)
	assert_eq(s.bullets.size(), 0, "both bullets consumed by mutual cancel")
	assert_eq(s.grid.get_brick(5, 6), TileGrid.BRICK_FULL,
			"brick must NOT be eroded — cancel preempts vs-tile")


func test_non_overlapping_player_enemy_bullets_dont_cancel() -> void:
	var s: TankState = _state()
	# Place far apart so cancel doesn't fire.
	s.bullets.append({
		"owner_kind": "player", "owner_idx": 0,
		"x": 50, "y": 50, "dir": TileGrid.DIR_E, "speed_sub": 0,
		"star": 0, "alive": true,
	})
	s.bullets.append({
		"owner_kind": "enemy", "owner_idx": 0,
		"x": 150, "y": 150, "dir": TileGrid.DIR_W, "speed_sub": 0,
		"star": 0, "alive": true,
	})
	s.tick(16)
	assert_eq(s.bullets.size(), 2, "distant bullets must coexist")


func test_iteration_order_player_then_enemy_by_idx() -> void:
	# Inject 4 bullets out of order, snapshot the iteration order, assert
	# it is [player#0, player#1, enemy#0, enemy#1] regardless of insertion.
	var s: TankState = _state()
	s.bullets.append({
		"owner_kind": "enemy", "owner_idx": 1, "x": 10, "y": 10,
		"dir": TileGrid.DIR_N, "speed_sub": 0, "star": 0, "alive": true,
	})
	s.bullets.append({
		"owner_kind": "player", "owner_idx": 1, "x": 20, "y": 20,
		"dir": TileGrid.DIR_N, "speed_sub": 0, "star": 0, "alive": true,
	})
	s.bullets.append({
		"owner_kind": "enemy", "owner_idx": 0, "x": 30, "y": 30,
		"dir": TileGrid.DIR_N, "speed_sub": 0, "star": 0, "alive": true,
	})
	s.bullets.append({
		"owner_kind": "player", "owner_idx": 0, "x": 40, "y": 40,
		"dir": TileGrid.DIR_N, "speed_sub": 0, "star": 0, "alive": true,
	})
	var order: Array = s._bullet_iteration_order()
	# Expect: player(idx=0) at insertion-3 → bullets[3]; player(idx=1) at
	# insertion-1 → bullets[1]; enemy(idx=0) at insertion-2 → bullets[2];
	# enemy(idx=1) at insertion-0 → bullets[0].
	assert_eq(order, [3, 1, 2, 0])
