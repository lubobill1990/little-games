extends GutTest
## Integration test for Galaga-style dive attacks (#30). Drives the state
## directly (no scene). Covers acceptance items #4–#9.

const Cfg := preload("res://scripts/invaders/core/invaders_config.gd")
const Lvl := preload("res://scripts/invaders/core/invaders_level.gd")
const State := preload("res://scripts/invaders/core/invaders_state.gd")
const Dive := preload("res://scripts/invaders/core/dive.gd")


func _state(seed_value: int = 0xD1) -> State:
	var cfg: Cfg = Cfg.new()
	var lvl: Lvl = Lvl.new()
	var s: State = State.create(seed_value, cfg, lvl)
	s.wave = 4   # past wave 1 so dives are legal
	return s


# --- Acceptance #4: kamikaze AABB hit consumes a life ---

func test_kamikaze_contact_costs_a_life() -> void:
	var s: State = _state()
	# Manually inject a kamikaze diver overlapping the player.
	var path: Dictionary = {
		"p0": Vector2(s.player_x, s.config.player_y),
		"p1": Vector2(s.player_x, s.config.player_y),
		"p2": Vector2(s.player_x, s.config.world_h + 8.0),
	}
	var d: Dictionary = Dive.make_diver(0, 0, path, Dive.MODE_KAMIKAZE, 0.5)
	# t=0 puts the diver right at the player.
	s.divers.append(d)
	var lives_before: int = s.lives
	var changed: bool = s._step_divers(0.001, 1)
	assert_true(changed)
	assert_eq(s.lives, lives_before - 1, "kamikaze contact deducts a life")
	# Diver was removed.
	assert_eq(s.divers.size(), 0)


# --- Acceptance #5: 2× score when killing a diving enemy ---

func test_diver_kill_awards_doubled_score() -> void:
	var s: State = _state()
	# Inject a diver from row 0 (kind 2 → row_values[2]=30).
	var path: Dictionary = {
		"p0": Vector2(80.0, 60.0),
		"p1": Vector2(80.0, 60.0),
		"p2": Vector2(80.0, 60.0),
	}
	var d: Dictionary = Dive.make_diver(0, 0, path, Dive.MODE_RETURNING, 0.5)
	s.divers.append(d)
	# Place player bullet on top of the diver.
	s.player_bullet_alive = true
	s.player_bullet_x = 80.0
	s.player_bullet_y = 60.0
	var hit: bool = s._player_bullet_vs_divers()
	assert_true(hit)
	# Row 0 kind = row_kinds[0]=2 → row_values[2]=20. Multiplier = 2 → 40.
	assert_eq(s.score, 20 * s.config.diver_score_multiplier)
	assert_false(s.player_bullet_alive)
	assert_eq(s.divers.size(), 0)


# --- Acceptance #6: returning diver lands on its slot, restoring live_mask ---

func test_returning_diver_restores_live_mask() -> void:
	var s: State = _state()
	# Pick row 4 col 5 (front row by default config).
	var r: int = 4
	var c: int = 5
	var idx: int = r * s.config.cols + c
	# Simulate the dive start: clear the slot and inject a returning diver
	# with a degenerate path that completes immediately.
	s.live_mask[idx] = 0
	var slot: Vector2 = Vector2(
			s.formation_ox + c * s.config.cell_w + s.config.cell_w * 0.5,
			s.formation_oy + r * s.config.cell_h + s.config.cell_h * 0.5)
	var path: Dictionary = {"p0": slot, "p1": slot, "p2": slot}
	var d: Dictionary = Dive.make_diver(r, c, path, Dive.MODE_RETURNING, 100.0)
	s.divers.append(d)
	# One step pushes t past 1.0 → completion path runs.
	var changed: bool = s._step_divers(0.1, 100)
	assert_true(changed)
	assert_eq(s.divers.size(), 0, "diver removed on completion")
	assert_eq(s.live_mask[idx], 1, "returning diver restored live_mask cell")


# --- Acceptance #7: kamikaze diver flying past world bottom is removed ---

func test_kamikaze_flies_off_and_is_removed_without_life_loss() -> void:
	var s: State = _state()
	# Place diver well below the player's row so AABB never overlaps.
	var below_y: float = s.config.world_h + 100.0
	var path: Dictionary = {
		"p0": Vector2(20.0, below_y),
		"p1": Vector2(20.0, below_y),
		"p2": Vector2(20.0, below_y),
	}
	var d: Dictionary = Dive.make_diver(0, 0, path, Dive.MODE_KAMIKAZE, 100.0)
	s.divers.append(d)
	var lives_before: int = s.lives
	# One advance: t exceeds 1.0 → completion removes the diver. No AABB hit
	# because the diver is far below the player.
	var changed: bool = s._step_divers(0.1, 100)
	assert_true(changed)
	assert_eq(s.divers.size(), 0)
	assert_eq(s.lives, lives_before, "no life lost when kamikaze exits cleanly")


# --- Acceptance #9: wave change clears active divers ---

func test_advance_wave_clears_divers() -> void:
	var s: State = _state()
	# Inject two divers.
	var path: Dictionary = {
		"p0": Vector2(50.0, 60.0),
		"p1": Vector2(50.0, 60.0),
		"p2": Vector2(50.0, 60.0),
	}
	s.divers.append(Dive.make_diver(0, 0, path, Dive.MODE_RETURNING, 0.5))
	s.divers.append(Dive.make_diver(0, 1, path, Dive.MODE_KAMIKAZE, 0.5))
	# Kill formation so _advance_wave fires.
	for i in range(s.live_mask.size()):
		s.live_mask[i] = 0
	s._advance_wave()
	assert_eq(s.divers.size(), 0, "divers cleared on wave advance")
	assert_eq(s.last_dive_check_ms, 0, "dive cooldown reset on wave advance")


# --- Acceptance #10 sanity: wave-1 cores never spawn divers ---

func test_wave_1_never_spawns_divers() -> void:
	var cfg: Cfg = Cfg.new()
	var lvl: Lvl = Lvl.new()
	var s: State = State.create(0xA1, cfg, lvl)
	# Drive 10 seconds of ticks at wave 1; no divers should ever appear.
	var t: int = 0
	for i in range(625):
		t += 16
		s.tick(t)
	assert_eq(s.divers.size(), 0, "no divers at wave 1")


# --- Snapshot round-trip preserves divers ---

func test_snapshot_round_trip_preserves_divers() -> void:
	var s: State = _state()
	var path: Dictionary = {
		"p0": Vector2(10.0, 20.0),
		"p1": Vector2(50.0, 80.0),
		"p2": Vector2(90.0, 30.0),
	}
	s.divers.append(Dive.make_diver(2, 3, path, Dive.MODE_RETURNING, 0.5))
	s.last_dive_check_ms = 4321
	var snap: Dictionary = s.snapshot()
	var s2: State = State.from_snapshot(snap, Cfg.new(), Lvl.new())
	assert_eq(s2.divers.size(), 1)
	assert_eq(int(s2.divers[0]["row"]), 2)
	assert_eq(int(s2.divers[0]["col"]), 3)
	assert_eq(int(s2.divers[0]["mode"]), Dive.MODE_RETURNING)
	assert_eq(s2.last_dive_check_ms, 4321)
