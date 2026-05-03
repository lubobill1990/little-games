extends GutTest
## Game2048State — apply, win/lose, snapshot round-trip, determinism.

const Game2048Config := preload("res://scripts/g2048/core/g2048_config.gd")
const Game2048State := preload("res://scripts/g2048/core/g2048_state.gd")
const Planner := preload("res://scripts/g2048/core/g2048_planner.gd")


func _cfg(size: int = 4, target: int = 2048, four_p: float = 0.1) -> Game2048Config:
	var c: Game2048Config = Game2048Config.new()
	c.size = size
	c.target_value = target
	c.four_probability = four_p
	return c


# --- Acceptance #1: determinism ---

func test_same_seed_same_inputs_same_snapshot_stream() -> void:
	var a: Game2048State = Game2048State.create(42, _cfg())
	var b: Game2048State = Game2048State.create(42, _cfg())
	# Identical starter spawns.
	assert_eq(a.snapshot()["grid"], b.snapshot()["grid"])
	# Identical move sequences: drive both with the same dir sequence.
	var seq: Array[int] = [
		Game2048State.Dir.LEFT, Game2048State.Dir.UP,
		Game2048State.Dir.RIGHT, Game2048State.Dir.DOWN,
	]
	for d in seq:
		a.apply(d)
		b.apply(d)
		assert_eq(a.snapshot(), b.snapshot(), "diverged after dir %d" % d)


# --- Acceptance #3: no-op move spawns nothing, returns false ---

func test_noop_move_does_not_spawn_or_change_state() -> void:
	# Construct a state where LEFT is a no-op: a row of distinct values at top.
	# We can't directly seed the grid, so use snapshot/from_snapshot.
	var seed_state: Game2048State = Game2048State.create(1, _cfg())
	var snap := seed_state.snapshot()
	# Hand-craft a grid with no LEFT moves possible.
	var hand_grid: Array = []
	for r in 4:
		var row: Array = []
		for c in 4:
			row.append({"id": 0, "value": 0})
		hand_grid.append(row)
	hand_grid[0] = [
		{"id": 1, "value": 2},
		{"id": 2, "value": 4},
		{"id": 3, "value": 8},
		{"id": 4, "value": 16},
	]
	snap["grid"] = hand_grid
	snap["next_id"] = 5
	var s: Game2048State = Game2048State.from_snapshot(snap)
	var p := s.plan(Game2048State.Dir.LEFT)
	assert_true(p.is_empty(), "plan should be empty")
	var changed: bool = s.commit(p)
	assert_false(changed, "commit of empty plan should return false")
	# No tile spawned, grid unchanged.
	assert_eq(s.snapshot()["grid"], hand_grid, "no-op should not mutate grid")


# --- Acceptance #4: tile spawn after non-empty commit ---

func test_apply_with_movement_spawns_exactly_one_tile() -> void:
	# Construct a simple movable scenario: [2,0,0,0] in row 0, rest empty.
	var s: Game2048State = Game2048State.create(7, _cfg())
	var snap := s.snapshot()
	var hand_grid: Array = []
	for r in 4:
		var row: Array = []
		for c in 4:
			row.append({"id": 0, "value": 0})
		hand_grid.append(row)
	hand_grid[0][0] = {"id": 1, "value": 2}
	snap["grid"] = hand_grid
	snap["next_id"] = 2
	var s2: Game2048State = Game2048State.from_snapshot(snap)
	var changed: bool = s2.apply(Game2048State.Dir.RIGHT)
	assert_true(changed)
	# Count non-zero cells: should be 2 (slid tile + new spawn).
	var grid_after: Array = s2.snapshot()["grid"]
	var non_zero: int = 0
	for r in 4:
		for c in 4:
			if int(grid_after[r][c]["value"]) != 0:
				non_zero += 1
	assert_eq(non_zero, 2, "expected exactly 2 tiles after apply (slid + spawned)")
	# Spawned tile is value 2 or 4.
	# Find the new spawn (id != 1).
	var spawned_value: int = -1
	for r in 4:
		for c in 4:
			var cell: Dictionary = grid_after[r][c]
			if int(cell["id"]) > 1:
				spawned_value = int(cell["value"])
	assert_true(spawned_value == 2 or spawned_value == 4, "spawn value must be 2 or 4")


# --- Acceptance #5: win flag becomes true at target, stays true ---

func test_won_flag_flips_at_target_and_stays_true() -> void:
	# Use a small target so it triggers easily without scripting many merges.
	var cfg: Game2048Config = _cfg(4, 8, 0.0)  # target=8, no 4-spawns
	var s: Game2048State = Game2048State.create(3, cfg)
	# Hand-craft a state with two 4s adjacent so LEFT merges them to 8.
	var snap := s.snapshot()
	var hand_grid: Array = []
	for r in 4:
		var row: Array = []
		for c in 4:
			row.append({"id": 0, "value": 0})
		hand_grid.append(row)
	hand_grid[0][0] = {"id": 1, "value": 4}
	hand_grid[0][1] = {"id": 2, "value": 4}
	snap["grid"] = hand_grid
	snap["next_id"] = 3
	var s2: Game2048State = Game2048State.from_snapshot(snap)
	assert_false(s2.is_won())
	s2.apply(Game2048State.Dir.LEFT)  # 4+4 → 8 = target
	assert_true(s2.is_won(), "won should be true once a tile reaches target")
	# Continue playing — won remains true regardless.
	s2.apply(Game2048State.Dir.RIGHT)
	assert_true(s2.is_won(), "won must stay true (irreversible)")


# --- Acceptance #6: lose detection ---

func test_is_lost_full_unmergeable_grid() -> void:
	var cfg: Game2048Config = _cfg(4, 2048)
	var s: Game2048State = Game2048State.create(1, cfg)
	var snap := s.snapshot()
	# Checkerboard-ish: no two adjacent equal cells.
	var values := [
		[2, 4, 2, 4],
		[4, 2, 4, 2],
		[2, 4, 2, 4],
		[4, 2, 4, 2],
	]
	var hand_grid: Array = []
	var nid: int = 1
	for r in 4:
		var row: Array = []
		for c in 4:
			row.append({"id": nid, "value": values[r][c]})
			nid += 1
		hand_grid.append(row)
	snap["grid"] = hand_grid
	snap["next_id"] = nid
	var s2: Game2048State = Game2048State.from_snapshot(snap)
	assert_true(s2.is_lost(), "checkerboard 2/4 grid has no legal move")


func test_is_lost_full_with_one_pair_returns_false() -> void:
	var cfg: Game2048Config = _cfg(4, 2048)
	var s: Game2048State = Game2048State.create(1, cfg)
	var snap := s.snapshot()
	# Same as above but introduce one adjacent pair: row 0 cols 0,1 both = 2.
	var values := [
		[2, 2, 2, 4],
		[4, 2, 4, 2],
		[2, 4, 2, 4],
		[4, 2, 4, 2],
	]
	var hand_grid: Array = []
	var nid: int = 1
	for r in 4:
		var row: Array = []
		for c in 4:
			row.append({"id": nid, "value": values[r][c]})
			nid += 1
		hand_grid.append(row)
	snap["grid"] = hand_grid
	snap["next_id"] = nid
	var s2: Game2048State = Game2048State.from_snapshot(snap)
	assert_false(s2.is_lost(), "row 0 cols 0,1 both 2 → at least one legal move")


func test_is_lost_empty_cell_means_not_lost() -> void:
	var s: Game2048State = Game2048State.create(1, _cfg())
	# Fresh state has 14 empty cells out of 16 → not lost.
	assert_false(s.is_lost())


# --- Acceptance #7: snapshot round-trip ---

func test_snapshot_round_trip_preserves_full_state() -> void:
	var s: Game2048State = Game2048State.create(99, _cfg())
	# Run a handful of moves to pick up score, ids, rng state divergence.
	s.apply(Game2048State.Dir.LEFT)
	s.apply(Game2048State.Dir.UP)
	s.apply(Game2048State.Dir.RIGHT)
	var snap := s.snapshot()
	var rebuilt: Game2048State = Game2048State.from_snapshot(snap)
	assert_eq(rebuilt.snapshot(), snap, "round-trip mismatch")
	# Continue both — they must stay in lockstep.
	s.apply(Game2048State.Dir.DOWN)
	rebuilt.apply(Game2048State.Dir.DOWN)
	assert_eq(rebuilt.snapshot(), s.snapshot(), "post-round-trip divergence")


func test_snapshot_has_version_field() -> void:
	var s: Game2048State = Game2048State.create(1, _cfg())
	var snap := s.snapshot()
	assert_eq(snap["version"], 1)


# --- Score accumulates across multiple merges ---

func test_score_accumulates_correctly() -> void:
	# Hand-craft: row 0 = [2,2,4,4]. Apply LEFT → score += 4 + 8 = 12.
	var s: Game2048State = Game2048State.create(1, _cfg())
	var snap := s.snapshot()
	var hand_grid: Array = []
	for r in 4:
		var row: Array = []
		for c in 4:
			row.append({"id": 0, "value": 0})
		hand_grid.append(row)
	hand_grid[0] = [
		{"id": 1, "value": 2},
		{"id": 2, "value": 2},
		{"id": 3, "value": 4},
		{"id": 4, "value": 4},
	]
	snap["grid"] = hand_grid
	snap["next_id"] = 5
	snap["score"] = 0
	var s2: Game2048State = Game2048State.from_snapshot(snap)
	s2.apply(Game2048State.Dir.LEFT)
	assert_eq(s2.snapshot()["score"], 12)
