extends GutTest
## powerup.gd — `star` effect.
## Acceptance #12a: star_level increments, capped at cfg.star_max.

const Powerup := preload("res://scripts/tank/core/powerup.gd")
const TankState := preload("res://scripts/tank/core/tank_state.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")


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


func test_star_increments_player_level() -> void:
	var s: TankState = _state()
	assert_eq(int(s.players[0]["star"]), 0)
	Powerup.apply(s, {"kind": "star", "col": 0, "row": 0, "spawned_ms": 0}, 0, 100)
	assert_eq(int(s.players[0]["star"]), 1)
	Powerup.apply(s, {"kind": "star", "col": 0, "row": 0, "spawned_ms": 0}, 0, 100)
	assert_eq(int(s.players[0]["star"]), 2)


func test_star_caps_at_star_max() -> void:
	var s: TankState = _state()
	for i in range(10):
		Powerup.apply(s, {"kind": "star", "col": 0, "row": 0, "spawned_ms": 0}, 0, 100)
	assert_eq(int(s.players[0]["star"]), s.config.star_max)
