extends GutTest
## g2048_planner — pure plan computation, all 4 directions, id tracking.

const Planner := preload("res://scripts/g2048/core/g2048_planner.gd")


# Helper: build a SQUARE id-grid from a 2D array of values, assigning
# sequential positive ids to non-zero cells. If `values` is shorter than its
# row width, the missing rows are padded with empty cells so n == cols. The
# planner requires n×n; this lets tests write `[[2,2,4,4]]` shorthand.
func _build(values: Array) -> Array:
	var rows: int = values.size()
	var cols: int = (values[0] as Array).size() if rows > 0 else 0
	var n: int = max(rows, cols)
	var g: Array = []
	var next_id: int = 1
	for r in n:
		var row: Array = []
		for c in n:
			var v: int = 0
			if r < rows and c < cols:
				v = int(values[r][c])
			if v == 0:
				row.append({"id": 0, "value": 0})
			else:
				row.append({"id": next_id, "value": v})
				next_id += 1
		g.append(row)
	return g


# Extract a value-only 2D array from a plan applied virtually. Useful to
# spot-check that the plan's net effect matches expected post-move values.
func _apply_plan_values(grid: Array, plan: Planner.MovePlan) -> Array:
	var n: int = grid.size()
	var out: Array = []
	for r in n:
		var row: Array = []
		row.resize(n)
		for c in n:
			row[c] = 0
		out.append(row)
	# Track which ids are explicitly placed.
	var placed: Dictionary = {}
	for m in plan.moves:
		var tm: Planner.TileMove = m
		placed[tm.id] = true
		if tm.merged_into == -1:
			out[tm.to_cell.y][tm.to_cell.x] = tm.new_value
	# Anything in original grid not placed stays put.
	for r in n:
		for c in n:
			var cell: Dictionary = grid[r][c]
			if int(cell["id"]) == 0:
				continue
			if not placed.has(int(cell["id"])):
				out[r][c] = int(cell["value"])
	return out


# --- LEFT direction (canonical) ---

func test_plan_left_two_pairs() -> void:
	# [2,2,4,4] → [4,8,0,0]
	var g := _build([[2, 2, 4, 4]])
	var p := Planner.plan(g, Planner.DIR_LEFT)
	assert_eq(p.gained_score, 12)
	var got := _apply_plan_values(g, p)
	assert_eq(got[0], [4, 8, 0, 0])


func test_plan_left_no_op_distinct() -> void:
	# Acceptance #3: no-merge plan is empty.
	var g := _build([[2, 4, 8, 16]])
	var p := Planner.plan(g, Planner.DIR_LEFT)
	assert_true(p.is_empty(), "plan should be empty when no movement possible")
	assert_eq(p.gained_score, 0)


func test_plan_left_compaction_only() -> void:
	# [0,2,0,2] → [4,0,0,0]: slide + merge across gap.
	var g := _build([[0, 2, 0, 2]])
	var p := Planner.plan(g, Planner.DIR_LEFT)
	var got := _apply_plan_values(g, p)
	assert_eq(got[0], [4, 0, 0, 0])


# --- RIGHT direction ---

func test_plan_right_two_pairs() -> void:
	# [2,2,4,4] RIGHT → [0,0,4,8] (rear pair merges first into rear).
	var g := _build([[2, 2, 4, 4]])
	var p := Planner.plan(g, Planner.DIR_RIGHT)
	assert_eq(p.gained_score, 12)
	var got := _apply_plan_values(g, p)
	assert_eq(got[0], [0, 0, 4, 8])


# --- UP direction (column-wise LEFT) ---

func test_plan_up_two_pairs_in_column() -> void:
	# Column 0 = [2,2,4,4] → [4,8,0,0]
	var g := _build([
		[2, 0, 0, 0],
		[2, 0, 0, 0],
		[4, 0, 0, 0],
		[4, 0, 0, 0],
	])
	var p := Planner.plan(g, Planner.DIR_UP)
	assert_eq(p.gained_score, 12)
	var got := _apply_plan_values(g, p)
	assert_eq(got, [
		[4, 0, 0, 0],
		[8, 0, 0, 0],
		[0, 0, 0, 0],
		[0, 0, 0, 0],
	])


# --- DOWN direction ---

func test_plan_down_two_pairs_in_column() -> void:
	# Column 0 = [2,2,4,4] going DOWN → [0,0,4,8]
	var g := _build([
		[2, 0, 0, 0],
		[2, 0, 0, 0],
		[4, 0, 0, 0],
		[4, 0, 0, 0],
	])
	var p := Planner.plan(g, Planner.DIR_DOWN)
	var got := _apply_plan_values(g, p)
	assert_eq(got, [
		[0, 0, 0, 0],
		[0, 0, 0, 0],
		[4, 0, 0, 0],
		[8, 0, 0, 0],
	])


# --- Tile id tracking ---

func test_plan_left_merge_survivor_is_leading_tile() -> void:
	# Row [2(id=1), 2(id=2), 0, 0] LEFT-merges; survivor = id=1 (leading).
	var g := _build([[2, 2, 0, 0]])
	var p := Planner.plan(g, Planner.DIR_LEFT)
	# Two TileMoves: survivor (id=1, no movement, merged_into=-1, value=4)
	# and dier (id=2, slides 1→0, merged_into=1).
	# Note: survivor at column 0 doesn't move (front_c == out_c == 0), so its
	# slide is skipped — but the merge path emits both records regardless.
	# Find the dier and assert its merged_into matches the leading tile id.
	var dier: Planner.TileMove = null
	for m in p.moves:
		var tm: Planner.TileMove = m
		if tm.merged_into != -1:
			dier = tm
			break
	assert_not_null(dier)
	assert_eq(dier.id, 2, "rear tile (id=2) should be the dier")
	assert_eq(dier.merged_into, 1, "dier should merge INTO leading tile (id=1)")
	assert_eq(dier.from_cell, Vector2i(1, 0))
	assert_eq(dier.to_cell, Vector2i(0, 0))


func test_plan_right_merge_survivor_is_leading_tile() -> void:
	# Row [2(id=1), 2(id=2), 0, 0] RIGHT → both end at column 3, value 4.
	# Going RIGHT, the LEADING tile (closer to direction) is id=2.
	var g := _build([[2, 2, 0, 0]])
	var p := Planner.plan(g, Planner.DIR_RIGHT)
	var dier: Planner.TileMove = null
	for m in p.moves:
		var tm: Planner.TileMove = m
		if tm.merged_into != -1:
			dier = tm
			break
	assert_not_null(dier)
	assert_eq(dier.id, 1, "rear tile going RIGHT is id=1")
	assert_eq(dier.merged_into, 2, "should merge INTO leading id=2")


# --- Purity (acceptance #8): plan does not mutate input ---

func test_plan_does_not_mutate_input_grid() -> void:
	var g := _build([[2, 2, 4, 4]])
	# Snapshot the input by deep-copying its scalars.
	var before: Array = []
	for row in g:
		var copy_row: Array = []
		for cell in row:
			copy_row.append({"id": int(cell["id"]), "value": int(cell["value"])})
		before.append(copy_row)
	var _p := Planner.plan(g, Planner.DIR_LEFT)
	for r in g.size():
		for c in g[r].size():
			assert_eq(g[r][c]["id"], before[r][c]["id"], "id mutated at (%d,%d)" % [r, c])
			assert_eq(g[r][c]["value"], before[r][c]["value"], "value mutated at (%d,%d)" % [r, c])
