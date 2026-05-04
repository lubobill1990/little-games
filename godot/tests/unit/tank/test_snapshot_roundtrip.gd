extends GutTest
## snapshot/restore — bit-equal round-trip across 5 hand-built scenarios
## (acceptance #17). Schema includes version=1, reserved effects=[],
## reserved vs_mode=null.

const TankState := preload("res://scripts/tank/core/tank_state.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")
const TankEntity := preload("res://scripts/tank/core/tank_entity.gd")
const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")
const Powerup := preload("res://scripts/tank/core/powerup.gd")


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


func _level_2p() -> String:
	var rows: PackedStringArray = PackedStringArray()
	rows.append("E.E.E.E.E....")
	for r in range(1, 11):
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
		var bonus: String = " +bonus" if (i == 3 or i == 10 or i == 17) else ""
		out += "basic" + bonus + "\n"
	return out


func _assert_byte_equal(a: Dictionary, b: Dictionary) -> void:
	# Sort keys for stable diff. Compare as JSON strings — Godot's deep
	# equality on Dictionary is strict, but JSON comparison gives a
	# readable diff when something drifts (and snapshot values are all
	# JSON-serialisable: ints, strings, bools, packed-byte-arrays as
	# arrays, nested arrays/dicts).
	var ja: String = JSON.stringify(_to_jsonable(a))
	var jb: String = JSON.stringify(_to_jsonable(b))
	assert_eq(ja, jb)


static func _to_jsonable(v: Variant) -> Variant:
	# PackedByteArray → Array. Recursive into Array/Dictionary.
	if v is PackedByteArray:
		var out: Array = []
		for byte in (v as PackedByteArray):
			out.append(byte)
		return out
	if v is Array:
		var out2: Array = []
		for it in (v as Array):
			out2.append(_to_jsonable(it))
		return out2
	if v is Dictionary:
		var out3: Dictionary = {}
		var keys: Array = (v as Dictionary).keys()
		keys.sort()
		for k in keys:
			out3[k] = _to_jsonable((v as Dictionary)[k])
		return out3
	return v


# --- 5 scenarios ---

func test_scenario_a_fresh_state() -> void:
	var s: TankState = TankState.create(42, _level_1p(), _roster(), 1, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	var snap1: Dictionary = s.snapshot()
	var s2: TankState = TankState.from_snapshot(snap1)
	assert_not_null(s2)
	var snap2: Dictionary = s2.snapshot()
	_assert_byte_equal(snap1, snap2)


func test_scenario_b_after_some_ticks() -> void:
	var s: TankState = TankState.create(42, _level_1p(), _roster(), 1, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	# Tick a bunch — spawn fires, AI runs, RNG cursors advance.
	var t: int = 16
	for k in range(50):
		s.tick(t)
		t += 16
	var snap1: Dictionary = s.snapshot()
	var s2: TankState = TankState.from_snapshot(snap1)
	var snap2: Dictionary = s2.snapshot()
	_assert_byte_equal(snap1, snap2)


func test_scenario_c_with_bullets_and_powerup() -> void:
	var s: TankState = TankState.create(42, _level_1p(), _roster(), 1, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	# Inject mixed bullets + a power-up on the field + an active shovel.
	s.bullets.append({
		"owner_kind": "player", "owner_idx": 0,
		"x": 50, "y": 60, "dir": TileGrid.DIR_N, "speed_sub": 4,
		"star": 1, "alive": true,
	})
	s.bullets.append({
		"owner_kind": "enemy", "owner_idx": 2,
		"x": 100, "y": 80, "dir": TileGrid.DIR_S, "speed_sub": 6,
		"star": 0, "alive": true,
	})
	s.powerup = {"kind": "ship", "col": 5, "row": 5, "spawned_ms": 100}
	# Shovel state with prior captured.
	s.flags["shovel_until_ms"] = 5000
	s.flags["shovel_prior"] = [
		[5, 11, TileGrid.TILE_EMPTY, TileGrid.BRICK_FULL],
		[6, 11, TileGrid.TILE_BRICK, TileGrid.BRICK_BOTTOM_GONE],
	]
	s.flags["freeze_until_ms"] = 3000
	var snap1: Dictionary = s.snapshot()
	var s2: TankState = TankState.from_snapshot(snap1)
	var snap2: Dictionary = s2.snapshot()
	_assert_byte_equal(snap1, snap2)


func test_scenario_d_2p_with_eroded_bricks() -> void:
	var s: TankState = TankState.create(7, _level_2p(), _roster(), 2, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	# Erode some bricks manually (simulate gameplay history).
	s.grid.set_tile(3, 3, TileGrid.TILE_BRICK)
	s.grid.set_brick(3, 3, TileGrid.BRICK_BOTTOM_GONE)
	s.grid.set_tile(4, 4, TileGrid.TILE_BRICK)
	s.grid.set_brick(4, 4, TileGrid.BRICK_LEFT_GONE)
	# Player upgrades.
	s.players[0]["star"] = 3
	s.players[1]["has_ship"] = true
	s.players[1]["helmet_until_ms"] = 9999
	# Some scores.
	s.scores[0] = 1500
	s.scores[1] = 800
	var snap1: Dictionary = s.snapshot()
	var s2: TankState = TankState.from_snapshot(snap1)
	var snap2: Dictionary = s2.snapshot()
	_assert_byte_equal(snap1, snap2)


func test_scenario_e_dead_player_pending_respawn() -> void:
	var s: TankState = TankState.create(11, _level_1p(), _roster(), 1, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	s.players[0]["alive"] = false
	s.players[0]["respawn_at_ms"] = 5000
	s.lives_arr[0] = 1
	# Add some dead enemies (we DON'T prune them — they stay in the array
	# so bullet owner_idx references stay valid).
	for i in range(3):
		var e: Dictionary = TankEntity.make_enemy("basic", 0, 0, false, s.config)
		e["alive"] = false
		s.enemies.append(e)
	var snap1: Dictionary = s.snapshot()
	var s2: TankState = TankState.from_snapshot(snap1)
	var snap2: Dictionary = s2.snapshot()
	_assert_byte_equal(snap1, snap2)


# --- schema invariants ---

func test_snapshot_has_version_and_reserved_fields() -> void:
	var s: TankState = TankState.create(42, _level_1p(), _roster(), 1, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	var snap: Dictionary = s.snapshot()
	assert_eq(int(snap["version"]), 1)
	assert_true(snap.has("effects"))
	assert_eq((snap["effects"] as Array).size(), 0)
	assert_true(snap.has("vs_mode"))
	assert_eq(snap["vs_mode"], null)


func test_from_snapshot_rejects_unknown_version() -> void:
	var snap: Dictionary = {"version": 999}
	var s: TankState = TankState.from_snapshot(snap)
	assert_eq(s, null)
	assert_push_error("unsupported version")


func test_snapshot_replay_continues_deterministically() -> void:
	# After restore, ticking should produce the same trace as if we'd just
	# kept ticking the original — the litmus test that RNG cursors really
	# round-tripped.
	var s1: TankState = TankState.create(42, _level_1p(), _roster(), 1, TankConfig.new())
	assert_not_null(s1)
	s1.set_last_tick(0)
	var t: int = 16
	for k in range(40):
		s1.tick(t)
		t += 16
	var snap: Dictionary = s1.snapshot()
	# Continue ticking s1.
	for k in range(20):
		s1.tick(t)
		t += 16
	var trail1: Dictionary = s1.snapshot()
	# Restore and continue from the mid-point.
	var s2: TankState = TankState.from_snapshot(snap)
	var t2: int = int(snap["now_ms"]) + 16
	for k in range(20):
		s2.tick(t2)
		t2 += 16
	var trail2: Dictionary = s2.snapshot()
	_assert_byte_equal(trail1, trail2)
