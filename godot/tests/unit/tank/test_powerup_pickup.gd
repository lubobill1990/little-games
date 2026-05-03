extends GutTest
## powerup.gd — pickup tie-break + bonus-kill spawn (acceptance #11, #13).

const Powerup := preload("res://scripts/tank/core/powerup.gd")
const TankState := preload("res://scripts/tank/core/tank_state.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")
const TankEntity := preload("res://scripts/tank/core/tank_entity.gd")
const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")


func _level_2p() -> String:
	var rows: PackedStringArray = PackedStringArray()
	rows.append("E............")
	for r in range(1, 11):
		rows.append(".............")
	rows.append("P...P........")
	rows.append("......H......")
	var out: String = ""
	for r in rows:
		out += r + "\n"
	return out


func _level_1p() -> String:
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


func test_pickup_p1_wins_tie() -> void:
	var s: TankState = TankState.create(42, _level_2p(), _roster(), 2, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	# Place a power-up at tile (5, 5). Move both players' centers onto that
	# tile so both AABBs overlap simultaneously.
	s.powerup = {"kind": "star", "col": 5, "row": 5, "spawned_ms": 0}
	var cx: int = 5 * 16 + 8
	var cy: int = 5 * 16 + 8
	s.players[0]["x"] = cx
	s.players[0]["y"] = cy
	s.players[1]["x"] = cx
	s.players[1]["y"] = cy
	# Drain wave so spawn doesn't churn.
	s.wave_state["queue_index"] = s.roster.size()
	s.tick(16)
	assert_eq(int(s.players[0]["star"]), 1, "P1 wins the tie")
	assert_eq(int(s.players[1]["star"]), 0, "P2 gets nothing")
	assert_eq(s.powerup, null, "pickup consumed")


func test_pickup_p2_when_only_p2_overlaps() -> void:
	var s: TankState = TankState.create(42, _level_2p(), _roster(), 2, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	s.powerup = {"kind": "star", "col": 5, "row": 5, "spawned_ms": 0}
	# Put P1 far away; only P2 can overlap.
	s.players[0]["x"] = 16
	s.players[0]["y"] = 16
	s.players[1]["x"] = 5 * 16 + 8
	s.players[1]["y"] = 5 * 16 + 8
	s.wave_state["queue_index"] = s.roster.size()
	s.tick(16)
	assert_eq(int(s.players[1]["star"]), 1)
	assert_eq(int(s.players[0]["star"]), 0)


func test_bonus_enemy_kill_spawns_powerup() -> void:
	var s: TankState = TankState.create(42, _level_1p(), _roster(), 1, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	# Hand-spawn a single bonus enemy at row 5.
	var en: Dictionary = TankEntity.make_enemy("basic", 5, 5, true, s.config)
	en["last_decision_ms"] = 1000000  # disable AI movement
	s.enemies.append(en)
	# Inject a player bullet about to overlap the enemy.
	s.bullets.append({
		"owner_kind": "player", "owner_idx": 0,
		"x": int(en["x"]), "y": int(en["y"]),
		"dir": TileGrid.DIR_N, "speed_sub": 0,
		"star": 0, "alive": true,
	})
	# Drain wave so spawn doesn't replace our hand-built setup.
	s.wave_state["queue_index"] = s.roster.size()
	# Pre-condition: no power-up.
	assert_eq(s.powerup, null)
	s.tick(16)
	# Enemy must be dead AND a power-up must have spawned.
	assert_false(s.enemies[0]["alive"])
	assert_true(s.powerup != null, "bonus kill must drop a power-up")


func test_non_bonus_kill_does_not_spawn_powerup() -> void:
	var s: TankState = TankState.create(42, _level_1p(), _roster(), 1, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	var en: Dictionary = TankEntity.make_enemy("basic", 5, 5, false, s.config)
	en["last_decision_ms"] = 1000000
	s.enemies.append(en)
	s.bullets.append({
		"owner_kind": "player", "owner_idx": 0,
		"x": int(en["x"]), "y": int(en["y"]),
		"dir": TileGrid.DIR_N, "speed_sub": 0,
		"star": 0, "alive": true,
	})
	s.wave_state["queue_index"] = s.roster.size()
	s.tick(16)
	assert_false(s.enemies[0]["alive"])
	assert_eq(s.powerup, null, "non-bonus kill must NOT drop a power-up")
