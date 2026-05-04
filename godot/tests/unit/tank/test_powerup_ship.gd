extends GutTest
## powerup.gd — `ship` effect.
## Acceptance #12f: picking player's `has_ship` becomes true; tank passes
## water; OTHER player still blocked. Ship does NOT grant bullet protection.

const Powerup := preload("res://scripts/tank/core/powerup.gd")
const TankState := preload("res://scripts/tank/core/tank_state.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")
const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")


func _level_2p() -> String:
	# 2P map with a water row separating the bottom from the rest.
	var rows: PackedStringArray = PackedStringArray()
	rows.append("E............")
	for r in range(1, 6):
		rows.append(".............")
	rows.append("WWWWWWWWWWWWW")  # row 6: full water row
	for r in range(7, 11):
		rows.append(".............")
	rows.append("P...P........")
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


func test_ship_sets_has_ship_for_picker_only() -> void:
	var s: TankState = TankState.create(42, _level_2p(), _roster(), 2, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	Powerup.apply(s, {"kind": "ship", "col": 0, "row": 0, "spawned_ms": 0}, 0, 100)
	assert_true(bool(s.players[0]["has_ship"]), "P1 must have ship")
	assert_false(bool(s.players[1]["has_ship"]), "P2 must NOT have ship")


func test_ship_lets_picker_cross_water_other_blocked() -> void:
	var s: TankState = TankState.create(42, _level_2p(), _roster(), 2, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	# Place P1 directly above the water row to test crossing.
	s.players[0]["x"] = 1 * 16 + 16  # center on col-1 boundary
	s.players[0]["y"] = 4 * 16 + 16  # row 4 center
	# Place P2 similarly.
	s.players[1]["x"] = 1 * 16 + 16
	s.players[1]["y"] = 4 * 16 + 16 + 16  # adjacent — but ALSO above water
	# Move P2 to a different lane.
	s.players[1]["x"] = 6 * 16 + 16  # col 6
	s.players[1]["y"] = 4 * 16 + 16
	# Drain wave so spawn doesn't churn.
	s.wave_state["queue_index"] = s.roster.size()
	# Give P1 the ship.
	Powerup.apply(s, {"kind": "ship", "col": 0, "row": 0, "spawned_ms": 0}, 0, 0)
	# Both players try to head south into water.
	s.set_player_intent(0, TileGrid.DIR_S)
	s.set_player_intent(1, TileGrid.DIR_S)
	var p1_y0: int = int(s.players[0]["y"])
	var p2_y0: int = int(s.players[1]["y"])
	# Tick many sub-steps to give them a chance.
	var t: int = 16
	for i in range(80):
		s.tick(t)
		t += 16
	# P1 should have moved (some y advance into / past the water row).
	# P2 should be stopped at the water boundary.
	assert_gt(int(s.players[0]["y"]), p1_y0, "P1 with ship must advance")
	# P2 should hit water and stop. Its y should advance up to but not past
	# the water boundary. Water row 6 starts at y=96; tank center reaches
	# y=96-16=80 max (right edge at boundary).
	assert_true(int(s.players[1]["y"]) <= 80, "P2 must be stopped at water")


func test_ship_does_not_protect_from_bullets() -> void:
	var s: TankState = TankState.create(42, _level_2p(), _roster(), 2, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	Powerup.apply(s, {"kind": "ship", "col": 0, "row": 0, "spawned_ms": 0}, 0, 0)
	# Place an enemy bullet on top of P1.
	var p: Dictionary = s.players[0]
	s.bullets.append({
		"owner_kind": "enemy", "owner_idx": 0,
		"x": int(p["x"]), "y": int(p["y"]), "dir": TileGrid.DIR_N, "speed_sub": 0,
		"star": 0, "alive": true,
	})
	s.tick(16)
	# Bullet must be consumed (the damage path runs even though P1 has ship).
	# Helmet is what blocks damage; ship doesn't.
	assert_eq(s.bullets.size(), 0)
