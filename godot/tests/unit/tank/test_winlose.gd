extends GutTest
## Win/lose conditions (acceptance #14, #15a/b/c, #16) + tunneling cap (#18).

const TankState := preload("res://scripts/tank/core/tank_state.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")
const TankEntity := preload("res://scripts/tank/core/tank_entity.gd")
const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")


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
	rows.append("E............")
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
		var bonus: String = " +bonus" if i < 3 else ""
		out += "basic" + bonus + "\n"
	return out


func _state_1p() -> TankState:
	var s: TankState = TankState.create(42, _level_1p(), _roster(), 1, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	return s


func _state_2p() -> TankState:
	var s: TankState = TankState.create(42, _level_2p(), _roster(), 2, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	return s


# --- tunneling cap (acceptance #18) ---

func test_tunneling_cap_violation_returns_null() -> void:
	var cfg: TankConfig = TankConfig.new()
	cfg.bullet_speed_normal_sub = 100  # way over half-brick threshold
	cfg.bullet_speed_fast_sub = 100
	var s: TankState = TankState.create(42, _level_1p(), _roster(), 1, cfg)
	assert_eq(s, null, "tunneling violation must reject create()")
	assert_push_error("tunneling cap violated")


func test_tunneling_ok_passes() -> void:
	var cfg: TankConfig = TankConfig.new()
	# Defaults: 4 / 6 sub-px; half-brick = 8. 6 < 8 → OK.
	assert_true(cfg.tunneling_ok())


# --- lives + respawn ---

func test_enemy_bullet_decrements_lives_when_no_helmet() -> void:
	var s: TankState = _state_1p()
	# Drain wave so spawn doesn't churn.
	s.wave_state["queue_index"] = s.roster.size()
	# Make sure helmet is OFF (default 0 < t_ms).
	assert_eq(int(s.players[0]["helmet_until_ms"]), 0)
	var p: Dictionary = s.players[0]
	var lives0: int = s.lives(0)
	# Place enemy bullet on top of player.
	s.bullets.append({
		"owner_kind": "enemy", "owner_idx": 0,
		"x": int(p["x"]), "y": int(p["y"]), "dir": TileGrid.DIR_N, "speed_sub": 0,
		"star": 0, "alive": true,
	})
	s.tick(16)
	assert_eq(s.lives(0), lives0 - 1, "lives must decrement")
	assert_false(s.players[0]["alive"], "player marked dead")
	assert_gt(int(s.players[0]["respawn_at_ms"]), 0, "respawn scheduled")


func test_player_respawns_after_timer() -> void:
	var s: TankState = _state_1p()
	s.wave_state["queue_index"] = s.roster.size()
	# Kill the player.
	s.players[0]["alive"] = false
	s.lives_arr[0] = 2
	s.players[0]["respawn_at_ms"] = 100
	s.set_last_tick(150)  # past respawn time
	s.tick(150 + 16)
	assert_true(s.players[0]["alive"], "must respawn")
	# Helmet armed (acceptance #12c-adjacent: helmet_on_respawn_ms).
	assert_gt(int(s.players[0]["helmet_until_ms"]), 0)


func test_enemy_on_spawn_tile_destroyed_on_respawn_no_score() -> void:
	# Acceptance #16: enemy parked on player's P tile → destroyed (no score).
	var s: TankState = _state_1p()
	s.wave_state["queue_index"] = s.roster.size()
	# Park an enemy on the P spawn tile.
	var spawn_col: int = int(s.player_spawn_slots[0][0])
	var spawn_row: int = int(s.player_spawn_slots[0][1])
	var en: Dictionary = TankEntity.make_enemy("basic", spawn_col, spawn_row, false, s.config)
	s.enemies.append(en)
	# Player ready to respawn.
	s.players[0]["alive"] = false
	s.lives_arr[0] = 1
	s.players[0]["respawn_at_ms"] = 50
	var score0: int = s.score(0)
	s.set_last_tick(100)
	s.tick(116)
	assert_true(s.players[0]["alive"], "respawned")
	assert_false(s.enemies[0]["alive"], "enemy destroyed by respawn")
	assert_eq(s.score(0), score0, "no score awarded for respawn-collision kill")


# --- game over ---

func test_base_destroyed_is_game_over() -> void:
	# Acceptance #15a: base destroyed → game over even if lives remain.
	var s: TankState = _state_1p()
	s.lives_arr[0] = 99
	# Manually clear the base tile.
	s.grid.set_tile(int(s.base_pos[0]), int(s.base_pos[1]), TileGrid.TILE_EMPTY)
	assert_true(s.is_game_over(), "base destroyed → game over")


func test_1p_game_over_when_lives_zero_and_dead() -> void:
	# Acceptance #15b.
	var s: TankState = _state_1p()
	s.lives_arr[0] = 0
	s.players[0]["alive"] = false
	s.players[0]["respawn_at_ms"] = 0
	assert_true(s.is_game_over())


func test_1p_not_game_over_while_lives_remain() -> void:
	var s: TankState = _state_1p()
	s.lives_arr[0] = 1
	s.players[0]["alive"] = false
	s.players[0]["respawn_at_ms"] = 1000
	s.now_ms = 0
	assert_false(s.is_game_over(), "respawn pending → not game over")


func test_2p_coop_one_player_dead_not_game_over() -> void:
	# Acceptance #15c: P1 lives==0 alone does not end the game.
	var s: TankState = _state_2p()
	s.lives_arr[0] = 0
	s.players[0]["alive"] = false
	s.lives_arr[1] = 2
	s.players[1]["alive"] = true
	assert_false(s.is_game_over())


func test_2p_coop_both_dead_is_game_over() -> void:
	var s: TankState = _state_2p()
	for idx in range(2):
		s.lives_arr[idx] = 0
		s.players[idx]["alive"] = false
		s.players[idx]["respawn_at_ms"] = 0
	assert_true(s.is_game_over())


# --- level clear ---

func test_level_clear_requires_all_enemies_killed() -> void:
	var s: TankState = _state_1p()
	s.wave_state["queue_index"] = s.roster.size()
	# No enemies, no enemy bullets, all roster spawned → cleared.
	assert_true(s.is_level_clear())


func test_level_clear_blocked_by_enemy_bullet_in_flight() -> void:
	# Acceptance #14: clearing all enemies with an enemy bullet alive
	# does NOT win until that bullet expires.
	var s: TankState = _state_1p()
	s.wave_state["queue_index"] = s.roster.size()
	s.bullets.append({
		"owner_kind": "enemy", "owner_idx": 0,
		"x": 50, "y": 50, "dir": TileGrid.DIR_N, "speed_sub": 4,
		"star": 0, "alive": true,
	})
	assert_false(s.is_level_clear())


func test_level_clear_blocked_by_unspawned_roster() -> void:
	var s: TankState = _state_1p()
	s.wave_state["queue_index"] = 5  # only 5/20 spawned
	assert_false(s.is_level_clear())


func test_level_clear_blocked_by_alive_enemy() -> void:
	var s: TankState = _state_1p()
	s.wave_state["queue_index"] = s.roster.size()
	s.enemies.append(TankEntity.make_enemy("basic", 4, 4, false, s.config))
	assert_false(s.is_level_clear())
