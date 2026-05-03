extends GutTest
## Full-level scripted-run smoke test (acceptance #22 coverage closer):
##   - Loads canonical level01.txt + level01.roster.txt.
##   - Drives the simulation for a bounded number of sub-steps with NO
##     player input (players sit at spawn, helmet expires after ~3s, then
##     they're sitting ducks). This is a stress test of the integration —
##     spawn → AI → bullets → power-ups → win/lose all run together.
##   - Verifies invariants throughout: enemy cap respected, no negative
##     scores, snapshot stays serialisable. At the end, asserts the run
##     terminated (game-over OR level-clear) within budget.
##   - Re-runs with the same seed and asserts byte-equal final snapshot —
##     proves determinism end-to-end across all subsystems.

const TankState := preload("res://scripts/tank/core/tank_state.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")
const TankLevel := preload("res://scripts/tank/core/tank_level.gd")
const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")

# 60 simulated seconds (3750 sub-steps at 16 ms) is plenty for one of:
#   - the 4 enemy-spawn slots feed 20 enemies and the player's bullets
#     (or the enemy's own attrition) eventually clear the wave, OR
#   - enemy bullets erode the base.
# Whichever fires, is_game_over() OR is_level_clear() must hold.
const TICK_MS: int = 16
const MAX_SUB_STEPS: int = 60_000 / TICK_MS  # 3750


func _read_text(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "fixture missing: %s" % path)
	var text: String = f.get_as_text()
	f.close()
	return text


func _drive(seed: int, max_steps: int) -> Dictionary:
	# Returns {"state": TankState, "steps": int, "outcome": String}.
	var tiles: String = _read_text("res://tests/unit/tank/fixtures/level01.txt")
	var roster: String = _read_text("res://tests/unit/tank/fixtures/level01.roster.txt")
	var s: TankState = TankState.create(seed, tiles, roster, 2, TankConfig.new())
	assert_not_null(s, "create() must succeed for seed %d" % seed)
	s.set_last_tick(0)
	var t: int = TICK_MS
	var n: int = 0
	var outcome: String = "timeout"
	while n < max_steps:
		s.tick(t)
		# Mid-run invariants — kept cheap so they can run every sub-step.
		assert_true(s.score(0) >= 0)
		assert_true(s.score(1) >= 0)
		assert_true(s.lives(0) >= 0)
		assert_true(s.lives(1) >= 0)
		var live_enemies: int = 0
		for e in s.enemies:
			if e["alive"]:
				live_enemies += 1
		assert_true(live_enemies <= s.config.max_alive_enemies,
				"enemy cap respected (got %d, cap %d)" % [live_enemies, s.config.max_alive_enemies])
		if s.is_game_over():
			outcome = "game_over"
			break
		if s.is_level_clear():
			outcome = "level_clear"
			break
		t += TICK_MS
		n += 1
	return {"state": s, "steps": n, "outcome": outcome}


func test_smoke_seed42_terminates() -> void:
	var run: Dictionary = _drive(42, MAX_SUB_STEPS)
	# Either outcome is acceptable; what we care about is that the run
	# reached a terminal state within the budget. Helmet expires at 3s,
	# enemies fire ~every couple of seconds, base is 2 tiles from P-spots
	# — game-over is the typical outcome for an idle player.
	assert_ne(run["outcome"], "timeout",
			"run must terminate within %d sub-steps (took %d, outcome=%s)" \
				% [MAX_SUB_STEPS, int(run["steps"]), String(run["outcome"])])
	# Sanity: a snapshot of the terminal state is still serialisable.
	var snap: Dictionary = (run["state"] as TankState).snapshot()
	assert_eq(int(snap["version"]), 1)


func test_smoke_seed42_deterministic() -> void:
	# Two independent runs with the same seed must produce byte-equal
	# final snapshots. Bound at 1500 sub-steps (24s) — long enough that
	# many spawn / AI / bullet / brick-erosion events accumulate, short
	# enough that the test runs in well under a second.
	var a: Dictionary = _drive(42, 1500)
	var b: Dictionary = _drive(42, 1500)
	assert_eq(int(a["steps"]), int(b["steps"]),
			"step count must match across deterministic runs")
	var snap_a: Dictionary = (a["state"] as TankState).snapshot()
	var snap_b: Dictionary = (b["state"] as TankState).snapshot()
	# Compare via JSON-stable string (PackedByteArray-aware) for a
	# readable diff if drift creeps in.
	assert_eq(JSON.stringify(_to_jsonable(snap_a)),
			JSON.stringify(_to_jsonable(snap_b)),
			"final snapshots must be byte-equal under same seed")


func test_smoke_different_seeds_diverge() -> void:
	# Cheap negative test: different seeds should produce different
	# final snapshots after enough sub-steps. Catches the bug where seed
	# isn't actually plumbed through to the sub-RNGs (silent regression).
	var a: Dictionary = _drive(42, 500)
	var b: Dictionary = _drive(99, 500)
	var snap_a: Dictionary = (a["state"] as TankState).snapshot()
	var snap_b: Dictionary = (b["state"] as TankState).snapshot()
	assert_ne(JSON.stringify(_to_jsonable(snap_a)),
			JSON.stringify(_to_jsonable(snap_b)),
			"different seeds must diverge")


# --- internal ---

static func _to_jsonable(v: Variant) -> Variant:
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
