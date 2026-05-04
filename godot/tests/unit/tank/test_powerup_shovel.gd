extends GutTest
## powerup.gd — `shovel` effect.
## Acceptance #12e: 8 base-surrounding tiles → S; after 20000 ms revert
## to the original tile-id + brick-erosion captured at activation.

const Powerup := preload("res://scripts/tank/core/powerup.gd")
const TankState := preload("res://scripts/tank/core/tank_state.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")
const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")


func _level_with_brick_ring() -> String:
	# Surround base (6, 11) with bricks so we can verify the snapshot
	# captures non-trivial pre-shovel state. Base sits one row above the
	# bottom so all 8 Moore neighbors are inside the world.
	# Layout (rows are 13 chars):
	#   row 10: .....BBB.....
	#   row 11: .....BHB.....   ← H is the base
	#   row 12: P....BBB.....
	var rows: PackedStringArray = PackedStringArray()
	rows.append("E............")           # 0
	for r in range(1, 10):
		rows.append(".............")       # 1..9
	rows.append(".....BBB.....")           # 10
	rows.append(".....BHB.....")           # 11
	rows.append("P....BBB.....")           # 12
	assert(rows.size() == 13)
	for r in rows:
		assert(r.length() == 13)
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


func test_shovel_replaces_neighbors_with_steel() -> void:
	var s: TankState = TankState.create(42, _level_with_brick_ring(), _roster(), 1, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	# Apply shovel.
	Powerup.apply(s, {"kind": "shovel", "col": 0, "row": 0, "spawned_ms": 0}, 0, 100)
	# Each of the 8 base-Moore-neighborhood tiles must now be steel.
	for off in Powerup.SHOVEL_OFFSETS:
		var c: int = int(s.base_pos[0]) + int(off[0])
		var r: int = int(s.base_pos[1]) + int(off[1])
		assert_eq(s.grid.get_tile(c, r), TileGrid.TILE_STEEL,
				"neighbor (%d,%d) must be steel" % [c, r])


func test_shovel_records_prior_for_revert() -> void:
	var s: TankState = TankState.create(42, _level_with_brick_ring(), _roster(), 1, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	Powerup.apply(s, {"kind": "shovel", "col": 0, "row": 0, "spawned_ms": 0}, 0, 100)
	var prior: Array = s.flags["shovel_prior"] as Array
	assert_eq(prior.size(), 8, "must capture all 8 neighbors")
	# First entry shape: [c, r, tile_id, brick_state].
	var entry: Array = prior[0] as Array
	assert_eq(entry.size(), 4)


func test_shovel_reverts_at_expiry() -> void:
	var s: TankState = TankState.create(42, _level_with_brick_ring(), _roster(), 1, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	# Snapshot expected pre-shovel state for the 8 neighbors.
	var expected: Array = []
	for off in Powerup.SHOVEL_OFFSETS:
		var c: int = int(s.base_pos[0]) + int(off[0])
		var r: int = int(s.base_pos[1]) + int(off[1])
		expected.append([c, r, s.grid.get_tile(c, r), s.grid.get_brick(c, r)])
	# Apply shovel at t=100, then advance time past expiry.
	Powerup.apply(s, {"kind": "shovel", "col": 0, "row": 0, "spawned_ms": 0}, 0, 100)
	# Drain wave so spawn doesn't churn during catch-up tick.
	s.wave_state["queue_index"] = s.roster.size()
	# Skip past the shovel window via set_last_tick (otherwise the catch-up
	# tick would burn the max_sub_steps_per_tick cap on no-op sub-steps).
	var expire_ms: int = 100 + s.config.shovel_pickup_ms + 32
	s.set_last_tick(expire_ms - 16)
	s.tick(expire_ms)
	for entry in expected:
		var c: int = int(entry[0])
		var r: int = int(entry[1])
		assert_eq(s.grid.get_tile(c, r), int(entry[2]),
				"tile (%d,%d) must revert to %d" % [c, r, int(entry[2])])
		assert_eq(s.grid.get_brick(c, r), int(entry[3]),
				"brick state at (%d,%d) must revert" % [c, r])
	assert_eq(int(s.flags["shovel_until_ms"]), 0, "expiry clears the flag")
