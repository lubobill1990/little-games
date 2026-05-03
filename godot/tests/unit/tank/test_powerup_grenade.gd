extends GutTest
## powerup.gd — `grenade` effect.
## Acceptance #12b: all live enemies removed; scores unchanged; player
## bullets in flight unaffected.

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


func test_grenade_kills_all_live_enemies() -> void:
	var s: TankState = _state()
	# Hand-spawn three enemies.
	s.enemies.append(TankEntity.make_enemy("basic", 0, 0, false, s.config))
	s.enemies.append(TankEntity.make_enemy("fast", 4, 0, false, s.config))
	s.enemies.append(TankEntity.make_enemy("armor", 8, 0, false, s.config))
	# Score baseline.
	var baseline: int = int(s.scores[0])
	Powerup.apply(s, {"kind": "grenade", "col": 0, "row": 0, "spawned_ms": 0}, 0, 100)
	for e in s.enemies:
		assert_false(e["alive"], "every enemy must die")
	assert_eq(int(s.scores[0]), baseline, "scores must NOT change on grenade")


func test_grenade_does_not_affect_bullets_in_flight() -> void:
	var s: TankState = _state()
	# Inject a player bullet.
	s.bullets.append({
		"owner_kind": "player", "owner_idx": 0,
		"x": 50, "y": 50, "dir": TileGrid.DIR_E, "speed_sub": 4,
		"star": 0, "alive": true,
	})
	Powerup.apply(s, {"kind": "grenade", "col": 0, "row": 0, "spawned_ms": 0}, 0, 100)
	assert_eq(s.bullets.size(), 1)
	assert_true(s.bullets[0]["alive"], "bullet must survive grenade")


func test_grenade_skips_dead_enemies() -> void:
	var s: TankState = _state()
	var dead: Dictionary = TankEntity.make_enemy("basic", 0, 0, false, s.config)
	dead["alive"] = false
	s.enemies.append(dead)
	# killed_count baseline 0; grenade should not credit dead enemies again.
	Powerup.apply(s, {"kind": "grenade", "col": 0, "row": 0, "spawned_ms": 0}, 0, 100)
	assert_eq(int(s.wave_state["killed_count"]), 0)
