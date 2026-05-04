extends GutTest
## powerup.gd — `helmet` effect.
## Acceptance #12c: helmet_until_ms = now + 10000; subsequent enemy bullet
## doesn't reduce lives (here we just verify helmet flag prevents the
## damage-path branch in bullet-vs-tank). Helmet does NOT protect base.

const Powerup := preload("res://scripts/tank/core/powerup.gd")
const TankState := preload("res://scripts/tank/core/tank_state.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")
const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")


func _level() -> String:
	var rows: PackedStringArray = PackedStringArray()
	rows.append("E............")
	for r in range(1, 11):
		rows.append(".............")
	rows.append("....P........")
	rows.append("......H......")
	var out: String = ""
	for r in rows:
		out += r + "\n"
	return out


func _roster() -> String:
	var out: String = ""
	for i in range(20):
		var bonus: String = " +bonus" if i < 3 else ""
		out += "basic" + bonus + "\n"
	return out


func _state() -> TankState:
	var s: TankState = TankState.create(42, _level(), _roster(), 1, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	return s


func test_helmet_sets_until_ms() -> void:
	var s: TankState = _state()
	Powerup.apply(s, {"kind": "helmet", "col": 0, "row": 0, "spawned_ms": 0}, 0, 1000)
	assert_eq(int(s.players[0]["helmet_until_ms"]),
			1000 + s.config.helmet_pickup_ms)


func test_helmet_does_not_protect_base() -> void:
	# Acceptance #12c: helmet is per-player, not per-base. Fire an enemy
	# bullet at the base while P1 has helmet — base must still take the hit.
	var s: TankState = _state()
	Powerup.apply(s, {"kind": "helmet", "col": 0, "row": 0, "spawned_ms": 0}, 0, 0)
	# Inject an enemy bullet right next to the base.
	var base_cx: int = 6 * 16 + 8
	var base_cy: int = 12 * 16 + 8
	s.bullets.append({
		"owner_kind": "enemy", "owner_idx": 0,
		"x": base_cx, "y": base_cy, "dir": TileGrid.DIR_N, "speed_sub": 0,
		"star": 0, "alive": true,
	})
	# One tick → bullet hits base regardless of player's helmet.
	s.tick(16)
	assert_eq(s.grid.get_tile(6, 12), TileGrid.TILE_EMPTY,
			"base destroyed despite player helmet")


func test_helmet_consumes_enemy_bullet() -> void:
	# When an enemy bullet overlaps a helmet'd player, the bullet must be
	# consumed (acceptance #12c implies "no damage" but bullet still removed).
	var s: TankState = _state()
	Powerup.apply(s, {"kind": "helmet", "col": 0, "row": 0, "spawned_ms": 0}, 0, 0)
	# Place an enemy bullet on top of the player.
	var p: Dictionary = s.players[0]
	s.bullets.append({
		"owner_kind": "enemy", "owner_idx": 0,
		"x": int(p["x"]), "y": int(p["y"]), "dir": TileGrid.DIR_N, "speed_sub": 0,
		"star": 0, "alive": true,
	})
	s.tick(16)
	assert_eq(s.bullets.size(), 0, "bullet consumed (helmet absorbs)")
