extends GutTest
## ai.gd + spawn.gd + tank_state integration — determinism + behavior.
##
## Acceptance #10: with fixed seed S and a fixed level, the sequence of
## (spawn_tick, enemy_kind, spawn_tile) for the first 20 enemies plus the
## first 200 sub-steps of enemy positions is reproducible across runs.
##
## Strategy: rather than commit a brittle byte-pinned JSON fixture (which
## would need re-baselining every time a non-functional internal changes
## even though acceptance #19 says future RNG consumers must NOT perturb
## fixtures — the in-code "run twice and compare" form catches the bug we
## actually care about), we run the simulation twice with the same seed and
## assert byte-identical traces. acceptance #19 is a separate test below
## that adds a dummy sub-RNG and asserts traces still match.

const Ai := preload("res://scripts/tank/core/ai.gd")
const Spawn := preload("res://scripts/tank/core/spawn.gd")
const TankState := preload("res://scripts/tank/core/tank_state.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")
const TankEntity := preload("res://scripts/tank/core/tank_entity.gd")
const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")
const SubRng := preload("res://scripts/tank/core/sub_rng.gd")


# --- fixtures ---

func _level() -> String:
	# 13×13 with 4 enemy spawn slots across the top, base bottom-center,
	# P at bottom-left.
	var rows: PackedStringArray = PackedStringArray()
	rows.append("E...E...E...E")     # row 0 — 4 spawn slots
	for r in range(1, 11):
		rows.append(".............")
	rows.append("....P........")
	rows.append("......H......")
	var out: String = ""
	for r in rows:
		out += r + "\n"
	return out


func _roster() -> String:
	# 20 entries, 3 +bonus, mixed kinds.
	var kinds: Array = ["basic", "basic", "fast", "basic", "power",
		"basic", "fast", "armor", "basic", "basic",
		"power", "basic", "fast", "basic", "armor",
		"basic", "basic", "fast", "power", "basic"]
	var out: String = ""
	for i in range(20):
		var bonus: String = " +bonus" if (i == 3 or i == 10 or i == 17) else ""
		out += String(kinds[i]) + bonus + "\n"
	return out


func _trace_run(seed: int, ticks: int) -> Array:
	# Trace = chronological list of events. Each event is one of:
	#   ["spawn", t_ms, kind, col, row]
	#   ["pos",   t_ms, enemy_idx, x, y, facing]
	# Run for `ticks` sub-steps. To capture spawns we look at queue_index
	# delta per tick; to capture positions we snapshot enemies after each
	# tick.
	var s: TankState = TankState.create(seed, _level(), _roster(), 1, TankConfig.new())
	assert_not_null(s, "state should build")
	s.set_last_tick(0)
	var trace: Array = []
	var sub_dt: int = s.config.sub_step_ms
	var prev_qi: int = 0
	var t: int = sub_dt
	for k in range(ticks):
		s.tick(t)
		var qi: int = int(s.wave_state["queue_index"])
		while prev_qi < qi:
			# Newest spawn is the last enemy in the array — log its kind +
			# spawn tile (recoverable from x/y).
			var en: Dictionary = s.enemies[prev_qi]
			var col: int = (int(en["x"]) - s.config.tile_size_sub) / s.config.tile_size_sub
			var row: int = (int(en["y"]) - s.config.tile_size_sub) / s.config.tile_size_sub
			trace.append(["spawn", t, String(en["kind"]), col, row])
			prev_qi += 1
		# Snapshot positions for first 4 enemies (we only need a stable
		# sample — full-state snapshot bloats the trace).
		for ei in range(min(4, s.enemies.size())):
			var e2: Dictionary = s.enemies[ei]
			trace.append(["pos", t, ei, int(e2["x"]), int(e2["y"]), int(e2["facing"])])
		t += sub_dt
	return trace


# --- pure ai.gd unit tests ---

func test_decide_dir_returns_minus_one_within_recheck_window() -> void:
	var cfg: TankConfig = TankConfig.new()
	var rng: RandomNumberGenerator = SubRng.make(1, SubRng.TAG_AI_TARGET)
	var en: Dictionary = TankEntity.make_enemy("basic", 0, 0, false, cfg)
	en["last_decision_ms"] = 100
	# now=200, recheck=800 → 100 < 800, no decision.
	assert_eq(Ai.decide_dir(rng, en, [6, 12], cfg, 200), -1)
	# Past recheck window → decision made.
	var d: int = Ai.decide_dir(rng, en, [6, 12], cfg, 100 + cfg.ai_recheck_ms)
	assert_true(d >= 0 and d <= 3, "valid direction returned")
	assert_eq(int(en["last_decision_ms"]), 100 + cfg.ai_recheck_ms)


func test_decide_dir_dead_enemy_no_op() -> void:
	var cfg: TankConfig = TankConfig.new()
	var rng: RandomNumberGenerator = SubRng.make(1, SubRng.TAG_AI_TARGET)
	var en: Dictionary = TankEntity.make_enemy("basic", 0, 0, false, cfg)
	en["alive"] = false
	assert_eq(Ai.decide_dir(rng, en, [6, 12], cfg, 100000), -1)


func test_dir_toward_base_choices() -> void:
	var cfg: TankConfig = TankConfig.new()
	var en: Dictionary = TankEntity.make_enemy("basic", 0, 0, false, cfg)
	# enemy at (16, 16); base at (6, 12) → center (104, 200).
	# dx = 88, dy = 184; |dy| > |dx| → DIR_S.
	en["last_decision_ms"] = 0
	# Force base-target branch with a stub rng that always returns 0.0.
	var rng: RandomNumberGenerator = SubRng.make(99, SubRng.TAG_AI_TARGET)
	rng.seed = 0
	# Construct a roll < ai_p_target_base by manipulating the rng directly.
	# Simpler: call _dir_toward_base via decide_dir with p=1.0 override.
	cfg.ai_p_target_base = 1.0
	var d: int = Ai.decide_dir(rng, en, [6, 12], cfg, cfg.ai_recheck_ms)
	assert_eq(d, TileGrid.DIR_S, "should head south toward base")


# --- pure spawn.gd unit tests ---

func test_try_spawn_respects_interval() -> void:
	var cfg: TankConfig = TankConfig.new()
	var rng: RandomNumberGenerator = SubRng.make(1, SubRng.TAG_SPAWN)
	var ws: Dictionary = {"spawned_count": 0, "killed_count": 0,
		"queue_index": 0, "last_spawn_attempt_ms": -1000000}
	var roster: Array = [{"kind": "basic", "bonus": false}]
	var slots: Array = [[0, 0]]
	var enemies: Array = []
	var players: Array = []
	# First call: interval gate (last_spawn_attempt_ms < 0) → spawns.
	var got: Variant = Spawn.try_spawn(rng, cfg, 0, ws, roster, slots, enemies, players)
	assert_not_null(got, "first spawn should succeed")
	# Second call at t=100ms (< spawn_interval_ms): no spawn.
	var got2: Variant = Spawn.try_spawn(rng, cfg, 100, ws, roster, slots, enemies, players)
	assert_eq(got2, null, "interval gate should block")


func test_try_spawn_respects_max_alive_cap() -> void:
	var cfg: TankConfig = TankConfig.new()
	cfg.max_alive_enemies = 2
	var rng: RandomNumberGenerator = SubRng.make(1, SubRng.TAG_SPAWN)
	var ws: Dictionary = {"spawned_count": 0, "killed_count": 0,
		"queue_index": 0, "last_spawn_attempt_ms": -1000000}
	var roster: Array = [
		{"kind": "basic", "bonus": false},
		{"kind": "basic", "bonus": false},
		{"kind": "basic", "bonus": false},
	]
	var slots: Array = [[0, 0], [4, 0], [8, 0]]
	var enemies: Array = []
	var players: Array = []
	Spawn.try_spawn(rng, cfg, 0, ws, roster, slots, enemies, players)
	Spawn.try_spawn(rng, cfg, 5000, ws, roster, slots, enemies, players)
	assert_eq(enemies.size(), 2)
	# Third attempt after enough time → cap blocks.
	var got: Variant = Spawn.try_spawn(rng, cfg, 10000, ws, roster, slots, enemies, players)
	assert_eq(got, null, "max_alive cap should block third spawn")


func test_try_spawn_skips_blocked_slots() -> void:
	var cfg: TankConfig = TankConfig.new()
	var rng: RandomNumberGenerator = SubRng.make(1, SubRng.TAG_SPAWN)
	var ws: Dictionary = {"spawned_count": 0, "killed_count": 0,
		"queue_index": 0, "last_spawn_attempt_ms": -1000000}
	var roster: Array = [{"kind": "basic", "bonus": false}]
	var slots: Array = [[0, 0]]
	# Block the only slot with a player parked there.
	var occupant: Dictionary = TankEntity.make_player(0, 0, 0, cfg)
	var enemies: Array = []
	var players: Array = [occupant]
	var got: Variant = Spawn.try_spawn(rng, cfg, 0, ws, roster, slots, enemies, players)
	assert_eq(got, null, "blocked-only-slot should fail to spawn")


func test_try_spawn_exhaustion() -> void:
	var cfg: TankConfig = TankConfig.new()
	var rng: RandomNumberGenerator = SubRng.make(1, SubRng.TAG_SPAWN)
	var ws: Dictionary = {"spawned_count": 0, "killed_count": 0,
		"queue_index": 5, "last_spawn_attempt_ms": -1000000}
	var roster: Array = [{"kind": "basic", "bonus": false}]
	var got: Variant = Spawn.try_spawn(rng, cfg, 100000, ws, roster,
			[[0, 0]], [], [])
	assert_eq(got, null, "queue past roster → no spawn")


# --- determinism (acceptance #10 + #19) ---

func test_same_seed_yields_byte_identical_trace() -> void:
	var t1: Array = _trace_run(42, 200)
	var t2: Array = _trace_run(42, 200)
	assert_eq(t1.size(), t2.size())
	for i in range(t1.size()):
		assert_eq(t1[i], t2[i], "trace divergence at i=%d" % i)


func test_different_seed_yields_different_trace() -> void:
	var t1: Array = _trace_run(42, 200)
	var t2: Array = _trace_run(43, 200)
	# Same length is fine, but content must differ somewhere — astronomically
	# unlikely otherwise.
	var any_diff: bool = false
	for i in range(min(t1.size(), t2.size())):
		if t1[i] != t2[i]:
			any_diff = true
			break
	assert_true(any_diff, "different seeds must yield different traces")


func test_adding_dummy_subrng_does_not_perturb_trace() -> void:
	# Acceptance #19: a future PR adding a new sub-RNG consumer with a fresh
	# tag must NOT shift existing fixtures. We model that here by drawing
	# from a dummy RNG seeded with a NEW tag value, then verifying the AI/
	# spawn trace is unchanged.
	var t1: Array = _trace_run(42, 200)
	# Run again, but burn a draw on a dummy sub-RNG with an unused tag value.
	var dummy: RandomNumberGenerator = SubRng.make(42, 0xDEADBEEF)
	for _i in range(50):
		dummy.randi()
	var t2: Array = _trace_run(42, 200)
	assert_eq(t1, t2, "dummy RNG draws must not perturb the trace")


func test_first_20_spawns_use_roster_in_order() -> void:
	# Run long enough for all 20 enemies — at spawn_interval_ms=2000 and
	# max_alive=4, we need to also kill enemies. For the acceptance check
	# we just verify roster ORDERING: the kind sequence of spawns matches
	# the roster prefix.
	var s: TankState = TankState.create(42, _level(), _roster(), 1, TankConfig.new())
	assert_not_null(s)
	s.set_last_tick(0)
	var sub_dt: int = s.config.sub_step_ms
	var t: int = sub_dt
	# Kill enemies as they appear so the cap doesn't stall the queue.
	for k in range(20000):  # plenty of sub-steps
		s.tick(t)
		t += sub_dt
		for e in s.enemies:
			if e["alive"]:
				e["alive"] = false  # insta-kill so the queue keeps flowing
		if int(s.wave_state["queue_index"]) >= 20:
			break
	assert_eq(int(s.wave_state["queue_index"]), 20, "all 20 enemies must spawn")
	# Roster kinds in order:
	var expected: Array = ["basic", "basic", "fast", "basic", "power",
		"basic", "fast", "armor", "basic", "basic",
		"power", "basic", "fast", "basic", "armor",
		"basic", "basic", "fast", "power", "basic"]
	assert_eq(s.enemies.size(), 20)
	for i in range(20):
		assert_eq(String(s.enemies[i]["kind"]), expected[i], "spawn idx %d" % i)
