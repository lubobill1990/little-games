extends GutTest
## powerup.gd — `timer` effect (a.k.a. freeze).
## Acceptance #12d: enemies don't move or fire for 5000 ms; players
## unaffected.

const Powerup := preload("res://scripts/tank/core/powerup.gd")
const TankState := preload("res://scripts/tank/core/tank_state.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")
const TankEntity := preload("res://scripts/tank/core/tank_entity.gd")
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


func test_timer_sets_freeze_flag() -> void:
	var s: TankState = _state()
	Powerup.apply(s, {"kind": "timer", "col": 0, "row": 0, "spawned_ms": 0}, 0, 1000)
	assert_eq(int(s.flags["freeze_until_ms"]),
			1000 + s.config.freeze_pickup_ms)


func test_timer_freezes_enemy_movement() -> void:
	# Hand-spawn an enemy and prove that during freeze, it doesn't move.
	var s: TankState = _state()
	var en: Dictionary = TankEntity.make_enemy("basic", 4, 4, false, s.config)
	en["facing"] = TileGrid.DIR_S
	en["last_decision_ms"] = 100000  # disable AI recheck so it keeps facing
	s.enemies.append(en)
	var x0: int = int(en["x"])
	var y0: int = int(en["y"])
	# Apply freeze for 5000ms starting at t=100. Tick a few sub-steps within
	# the freeze window.
	Powerup.apply(s, {"kind": "timer", "col": 0, "row": 0, "spawned_ms": 0}, 0, 100)
	s.set_last_tick(100)
	for i in range(5):
		s.tick(100 + (i + 1) * 16)
	assert_eq(int(s.enemies[0]["x"]), x0, "x unchanged while frozen")
	assert_eq(int(s.enemies[0]["y"]), y0, "y unchanged while frozen")


func test_timer_does_not_freeze_player_movement() -> void:
	var s: TankState = _state()
	# Move P1 to a clear spot where it has room to step east.
	s.players[0]["x"] = 16
	s.players[0]["y"] = 5 * 16 + 16
	# Drain wave so spawn doesn't churn.
	s.wave_state["queue_index"] = s.roster.size()
	Powerup.apply(s, {"kind": "timer", "col": 0, "row": 0, "spawned_ms": 0}, 0, 100)
	s.set_last_tick(100)
	# Player moves east — freeze must not affect us.
	s.set_player_intent(0, TileGrid.DIR_E)
	var p_x0: int = int(s.players[0]["x"])
	s.tick(100 + 16)
	assert_eq(int(s.players[0]["x"]), p_x0 + s.config.tank_speed_player_sub,
			"player must keep moving while freeze affects only enemies")


func test_timer_expires_naturally() -> void:
	var s: TankState = _state()
	var en: Dictionary = TankEntity.make_enemy("basic", 4, 4, false, s.config)
	en["facing"] = TileGrid.DIR_S
	en["last_decision_ms"] = 100000  # force facing-stable
	s.enemies.append(en)
	# Drain wave so the spawn phase doesn't add more enemies.
	s.wave_state["queue_index"] = s.roster.size()
	var y0: int = int(en["y"])
	Powerup.apply(s, {"kind": "timer", "col": 0, "row": 0, "spawned_ms": 0}, 0, 100)
	# Skip past the freeze window via set_last_tick so we don't burn the
	# max_sub_steps_per_tick cap on freeze-time ticks.
	s.set_last_tick(100 + s.config.freeze_pickup_ms + 16)
	# Now tick a few sub-steps after expiry.
	var t: int = 100 + s.config.freeze_pickup_ms + 16
	for i in range(5):
		t += 16
		s.tick(t)
	assert_ne(int(s.enemies[0]["y"]), y0, "enemy must move after freeze expires")
