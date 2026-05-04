extends GutTest
## tank_state.gd — create() lifecycle, set_player_intent + rail-snap end-to-end,
## request_fire edge-trigger, tick() sub-step movement, snapshot round-trip.
## Bullet/AI/win-lose tests live in their own files (added in later commits).

const TankGameState := preload("res://scripts/tank/core/tank_state.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")
const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")


func _good_tiles_2p() -> String:
	return "\n".join([
		".............",
		".....E.E.E...",
		".............",
		".BBB.SSSS....",
		".BBB.SSSS....",
		".BBB.SSSS....",
		".BBB.........",
		"......WWW....",
		"......WWW....",
		".....GGGGG...",
		".....GIIIG...",
		".....P.HP...E",
		".............",
	])


func _good_tiles_1p() -> String:
	return "\n".join([
		".............",
		".....E.E.E...",
		".............",
		".BBB.SSSS....",
		".BBB.SSSS....",
		".BBB.SSSS....",
		".BBB.........",
		"......WWW....",
		"......WWW....",
		".....GGGGG...",
		".....GIIIG...",
		".....P.H....E",
		".............",
	])


func _good_roster() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for i in range(20):
		var bonus_suffix: String = " +bonus" if (i == 3 or i == 10 or i == 17) else ""
		lines.append("basic%s" % bonus_suffix)
	return "\n".join(lines)


func _empty_grid_state(player_count: int = 1) -> TankGameState:
	# Build a state on a clean map (no obstacles around the player spawn).
	# Reuses _good_tiles for shape; tests that need a custom level supply
	# their own.
	var tiles: String = _good_tiles_2p() if player_count == 2 else _good_tiles_1p()
	return TankGameState.create(42, tiles, _good_roster(), player_count)


# --- create() ---

func test_create_returns_state_for_valid_inputs() -> void:
	var s: TankGameState = TankGameState.create(42, _good_tiles_2p(), _good_roster(), 2)
	assert_not_null(s)
	assert_eq(s.player_count(), 2)
	assert_eq(s.players.size(), 2)
	assert_eq(s.lives(0), s.config.player_lives_start)
	assert_eq(s.lives(1), s.config.player_lives_start)
	assert_eq(s.score(0), 0)
	assert_eq(s.score(1), 0)


func test_create_1p_has_one_player_only() -> void:
	var s: TankGameState = TankGameState.create(42, _good_tiles_1p(), _good_roster(), 1)
	assert_not_null(s)
	assert_eq(s.player_count(), 1)
	assert_eq(s.players.size(), 1)


func test_create_rejects_invalid_player_count() -> void:
	var s: TankGameState = TankGameState.create(42, _good_tiles_2p(), _good_roster(), 0)
	assert_null(s)
	assert_push_error("player_count must be 1 or 2")


func test_create_rejects_tunneling_violation() -> void:
	var bad_cfg: TankConfig = TankConfig.new()
	bad_cfg.bullet_speed_fast_sub = 64  # way too fast vs 8-sub-px half-brick
	var s: TankGameState = TankGameState.create(42, _good_tiles_2p(), _good_roster(), 2, bad_cfg)
	assert_null(s)
	assert_push_error("tunneling cap violated")


func test_create_propagates_level_parse_failure() -> void:
	# Bad roster (only 3 lines) → parse_level fails → create returns null.
	var s: TankGameState = TankGameState.create(42, _good_tiles_2p(), "basic\nbasic\nbasic\n", 2)
	assert_null(s)
	# Two errors get pushed: one inside tank_level.parse_roster, then a
	# wrap-up from create() so the stack trace bubbles up.
	assert_push_error("tank_level: roster")
	assert_push_error("level parse failed")


func test_create_finds_base_and_spawns() -> void:
	var s: TankGameState = TankGameState.create(42, _good_tiles_2p(), _good_roster(), 2)
	assert_eq(s.base_pos, [7, 11])
	assert_eq(s.player_spawn_slots.size(), 2)
	assert_eq(s.player_spawn_slots[0], [5, 11])
	assert_eq(s.player_spawn_slots[1], [8, 11])
	# Enemy spawns: 4 markers in the fixture.
	assert_eq(s.enemy_spawn_slots.size(), 4)


func test_create_grid_marks_brick_and_steel() -> void:
	var s: TankGameState = TankGameState.create(42, _good_tiles_2p(), _good_roster(), 2)
	# Row 3 col 1 is 'B'; col 5 is 'S' (per fixture).
	assert_eq(s.grid.get_tile(1, 3), TileGrid.TILE_BRICK)
	assert_eq(s.grid.get_tile(5, 3), TileGrid.TILE_STEEL)
	assert_eq(s.grid.get_tile(0, 0), TileGrid.TILE_EMPTY)


# --- set_player_intent ---

func test_set_player_intent_sets_facing_and_moving() -> void:
	var s: TankGameState = _empty_grid_state(1)
	s.set_player_intent(0, TileGrid.DIR_N)
	var p: Dictionary = s.players[0]
	assert_eq(p["facing"], TileGrid.DIR_N)
	assert_true(p["moving"])


func test_set_player_intent_minus_one_stops_keeps_facing() -> void:
	var s: TankGameState = _empty_grid_state(1)
	s.set_player_intent(0, TileGrid.DIR_E)
	s.set_player_intent(0, -1)
	var p: Dictionary = s.players[0]
	assert_false(p["moving"])
	assert_eq(p["facing"], TileGrid.DIR_E, "facing preserved on stop")


func test_set_player_intent_invalid_dir_is_noop() -> void:
	var s: TankGameState = _empty_grid_state(1)
	s.set_player_intent(0, TileGrid.DIR_N)
	# 99 is invalid → no-op.
	s.set_player_intent(0, 99)
	var p: Dictionary = s.players[0]
	assert_eq(p["facing"], TileGrid.DIR_N)
	assert_true(p["moving"])


func test_set_player_intent_for_p2_in_1p_is_noop() -> void:
	var s: TankGameState = _empty_grid_state(1)
	# Should not crash and should not alter p1.
	s.set_player_intent(1, TileGrid.DIR_E)
	var p1: Dictionary = s.players[0]
	assert_false(p1["moving"], "p1 untouched")


func test_set_player_intent_perpendicular_flip_snaps_offaxis() -> void:
	var s: TankGameState = _empty_grid_state(1)
	# Spawn is at (5, 11) → center (5*16+16, 11*16+16) = (96, 192).
	# Move N → facing becomes N; then nudge x off-rail manually and flip to E.
	s.set_player_intent(0, TileGrid.DIR_N)
	var p: Dictionary = s.players[0]
	# Manually drift y to 193 (off-rail). Re-issue intent E (perpendicular):
	p["y"] = 193
	s.set_player_intent(0, TileGrid.DIR_E)
	# Snap to nearest 4 = 192.
	assert_eq(p["y"], 192)
	assert_eq(p["facing"], TileGrid.DIR_E)


# --- request_fire / release_fire ---

func test_request_fire_first_call_succeeds() -> void:
	var s: TankGameState = _empty_grid_state(1)
	s.set_last_tick(0)
	assert_true(s.request_fire(0))


func test_request_fire_latched_blocks_holding() -> void:
	var s: TankGameState = _empty_grid_state(1)
	s.set_last_tick(0)
	assert_true(s.request_fire(0))
	# Holding the button (no release) → second request denied.
	assert_false(s.request_fire(0))


func test_release_fire_then_request_succeeds_after_cooldown() -> void:
	var s: TankGameState = _empty_grid_state(1)
	s.set_last_tick(0)
	assert_true(s.request_fire(0))
	s.release_fire(0)
	# Still within cooldown (200ms default) → blocked.
	assert_false(s.request_fire(0))
	# Advance time past cooldown.
	s.set_last_tick(1000)
	# First bullet still in flight would otherwise hit the max-bullets cap;
	# this test exercises cooldown semantics, so clear it to isolate.
	s.bullets.clear()
	assert_true(s.request_fire(0))


func test_request_fire_for_invalid_idx_returns_false() -> void:
	var s: TankGameState = _empty_grid_state(1)
	s.set_last_tick(0)
	assert_false(s.request_fire(1), "p2 idx in 1P mode")
	assert_false(s.request_fire(99))


# --- tick() movement ---

func test_tick_moves_player_in_facing_direction() -> void:
	var s: TankGameState = _empty_grid_state(1)
	# Place player on a clean patch in the upper-left (tiles 0..2 are all
	# empty in the 1P fixture). Center (24, 24) → AABB rows 0..2 cols 0..2.
	var p: Dictionary = s.players[0]
	p["x"] = 24
	p["y"] = 24
	s.set_player_intent(0, TileGrid.DIR_S)
	s.set_last_tick(0)
	# Advance enough for several sub-steps. With sub_step_ms=16 and
	# tank_speed_player_sub=1, 5 sub-steps move y by 5.
	var changed: bool = s.tick(80)
	assert_true(changed, "tick should report visible change")
	assert_eq(p["y"], 29)  # 24 + 5


func test_tick_no_change_when_intent_zero() -> void:
	var s: TankGameState = _empty_grid_state(1)
	s.set_last_tick(0)
	# No intent set → no player movement. But spawn still fires on first
	# sub-step because the wave queue hasn't been opened yet — drain the
	# roster so the spawn phase is a no-op too.
	s.wave_state["queue_index"] = s.roster.size()
	var changed: bool = s.tick(80)
	assert_false(changed)


func test_tick_caps_sub_steps_per_call() -> void:
	# Long dt should be capped to max_sub_steps_per_tick (default 8) so a
	# returning paused tab doesn't catch up forever in one call.
	var s: TankGameState = _empty_grid_state(1)
	var p: Dictionary = s.players[0]
	p["x"] = 24
	p["y"] = 24
	s.set_player_intent(0, TileGrid.DIR_S)
	s.set_last_tick(0)
	# 10 seconds of dt → would be 625 sub-steps if uncapped; cap is 8.
	s.tick(10000)
	assert_eq(p["y"], 24 + 8, "moved exactly 8 sub-steps")


func test_tick_initializes_clock_silently_on_first_call() -> void:
	var s: TankGameState = _empty_grid_state(1)
	# First tick after create() seeds the clock and returns false (no
	# stepping happens because dt is unknown).
	var changed: bool = s.tick(123)
	assert_false(changed)
	assert_eq(s.now_ms, 123)


func test_set_last_tick_aligns_clock_without_stepping() -> void:
	var s: TankGameState = _empty_grid_state(1)
	var p: Dictionary = s.players[0]
	p["x"] = 24
	p["y"] = 24
	s.set_player_intent(0, TileGrid.DIR_S)
	s.set_last_tick(1000)
	# tick(1016) should advance exactly one sub-step (1 sub-px).
	var changed: bool = s.tick(1016)
	assert_true(changed)
	assert_eq(p["y"], 25)


# --- snapshot round-trip ---

func test_snapshot_round_trip_byte_equal_after_create() -> void:
	var s: TankGameState = _empty_grid_state(2)
	var snap_a: Dictionary = s.snapshot()
	var s2: TankGameState = TankGameState.from_snapshot(snap_a)
	assert_not_null(s2)
	var snap_b: Dictionary = s2.snapshot()
	assert_eq(snap_a, snap_b, "snapshot round-trip must be byte-equal")


func test_snapshot_round_trip_after_movement() -> void:
	var s: TankGameState = _empty_grid_state(1)
	var p: Dictionary = s.players[0]
	p["x"] = 96
	p["y"] = 96
	s.set_player_intent(0, TileGrid.DIR_N)
	s.set_last_tick(0)
	s.tick(80)
	var snap_a: Dictionary = s.snapshot()
	var s2: TankGameState = TankGameState.from_snapshot(snap_a)
	var snap_b: Dictionary = s2.snapshot()
	assert_eq(snap_a, snap_b)


func test_snapshot_round_trip_after_brick_erosion() -> void:
	var s: TankGameState = _empty_grid_state(1)
	# Erode the (1, 3) brick (B per fixture) twice → DESTROYED.
	s.grid.erode_brick(1, 3, TileGrid.DIR_N)
	s.grid.erode_brick(1, 3, TileGrid.DIR_S)
	var snap_a: Dictionary = s.snapshot()
	var s2: TankGameState = TankGameState.from_snapshot(snap_a)
	var snap_b: Dictionary = s2.snapshot()
	assert_eq(snap_a, snap_b)
	# Sanity: restored tile is empty, brick state DESTROYED.
	assert_eq(s2.grid.get_tile(1, 3), TileGrid.TILE_EMPTY)


func test_snapshot_round_trip_preserves_rng_cursors() -> void:
	# Burn some RNG cycles in the original then snapshot/restore. Both
	# should produce the same next-draw value.
	var s: TankGameState = _empty_grid_state(1)
	for i in range(7):
		s._spawn_rng.randi()
	var snap_a: Dictionary = s.snapshot()
	var s2: TankGameState = TankGameState.from_snapshot(snap_a)
	var nxt_a: int = s._spawn_rng.randi()
	var nxt_b: int = s2._spawn_rng.randi()
	assert_eq(nxt_a, nxt_b)


func test_snapshot_has_reserved_fields() -> void:
	var s: TankGameState = _empty_grid_state(1)
	var snap: Dictionary = s.snapshot()
	assert_eq(snap["version"], 1)
	assert_true(snap.has("effects"))
	assert_eq(snap["effects"], [])
	assert_true(snap.has("vs_mode"))
	assert_eq(snap["vs_mode"], null)


func test_from_snapshot_rejects_unknown_version() -> void:
	var s: TankGameState = _empty_grid_state(1)
	var snap: Dictionary = s.snapshot()
	snap["version"] = 99
	var s2: TankGameState = TankGameState.from_snapshot(snap)
	assert_null(s2)
	assert_push_error("unsupported version")


# --- queries ---

func test_is_game_over_when_all_lives_zero() -> void:
	var s: TankGameState = _empty_grid_state(2)
	assert_false(s.is_game_over())
	# Lives==0 alone is not game-over while players are still alive on the
	# field (acceptance #15b/c — game-over needs all players dead AND no
	# respawn pending).
	s.lives_arr[0] = 0
	s.lives_arr[1] = 0
	assert_false(s.is_game_over(), "alive players still on the field")
	# Mark both dead and clear any respawn timer → now game-over.
	s.players[0]["alive"] = false
	s.players[0]["respawn_at_ms"] = 0
	s.players[1]["alive"] = false
	s.players[1]["respawn_at_ms"] = 0
	assert_true(s.is_game_over())


func test_score_and_lives_invalid_idx_returns_zero() -> void:
	var s: TankGameState = _empty_grid_state(1)
	assert_eq(s.score(99), 0)
	assert_eq(s.lives(99), 0)
	assert_eq(s.score(1), 0, "p2 in 1P → 0")
	assert_eq(s.lives(1), 0)
