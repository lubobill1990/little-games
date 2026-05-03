extends RefCounted
## Game2048State — pure 2048 rules + tile-id bookkeeping.
##
## Pure: no Node, no Engine timing, no signals. Drives via plan(dir) /
## commit(plan) / apply(dir). Tile ids are stable across moves; scenes use
## them to animate slides and merges from the MovePlan returned by plan().
##
## Per architecture.md "Snapshot diffs, not signals": state changes are
## surfaced via apply()'s bool return + snapshot() Dictionary diffs.

const Self := preload("res://scripts/g2048/core/g2048_state.gd")
const Game2048Config := preload("res://scripts/g2048/core/g2048_config.gd")
const Planner := preload("res://scripts/g2048/core/g2048_planner.gd")

const SCHEMA_VERSION: int = 1

enum Dir { LEFT = 0, RIGHT = 1, UP = 2, DOWN = 3 }

var config: Game2048Config
# id-grid: Array[Array[Dictionary]], rows×cols, each cell {id: int, value: int}.
# Empty cell: {id: 0, value: 0}. Ids are positive starting at 1.
var _grid: Array = []
var _score: int = 0
var _won: bool = false
var _next_id: int = 1
var _rng: RandomNumberGenerator


# --- Construction ---


static func create(game_seed: int, cfg: Game2048Config) -> Self:
	var s: Self = Self.new()
	s.config = cfg
	s._rng = RandomNumberGenerator.new()
	s._rng.seed = game_seed
	s._grid = _empty_grid(cfg.size)
	# Spawn two starter tiles per classic 2048 rules.
	s._spawn_random_tile()
	s._spawn_random_tile()
	return s


static func _empty_grid(n: int) -> Array:
	var g: Array = []
	for r in n:
		var row: Array = []
		for c in n:
			row.append({"id": 0, "value": 0})
		g.append(row)
	return g


# --- Public API ---


## Compute a MovePlan for direction `dir`. Pure — does NOT mutate state.
## Acceptance #8: tested independently of commit().
func plan(dir: int) -> Planner.MovePlan:
	return Planner.plan(_grid, dir)


## Apply a previously-planned move. Mutates state, spawns one random tile
## iff the plan was non-empty. Returns true iff state changed.
func commit(p: Planner.MovePlan) -> bool:
	if p == null or p.is_empty():
		return false
	# Build the next grid from the plan. Strategy:
	#  1. Start with an empty grid.
	#  2. For each TileMove with merged_into == -1 (slider or merge survivor),
	#     write {id, new_value} at to_cell.
	#  3. Tiles that were UNTOUCHED by the plan (no TileMove for their id)
	#     stay where they are. Detect those by collecting moved-ids and
	#     copying the rest from _grid to next_grid at original positions.
	#
	# Note: in classic 2048 every tile that is not blocked moves toward the
	# direction, so most plans touch every tile, but this is the safe path.
	var n: int = config.size
	var next_grid: Array = _empty_grid(n)
	var moved_ids: Dictionary = {}
	for m in p.moves:
		var tm: Planner.TileMove = m
		moved_ids[tm.id] = true

	# 1. Survivors (and pure sliders) write to to_cell with their new_value.
	#    Diers (merged_into != -1) just disappear — don't write anywhere.
	for m in p.moves:
		var tm: Planner.TileMove = m
		if tm.merged_into != -1:
			continue
		var to_c: Vector2i = tm.to_cell
		next_grid[to_c.y][to_c.x] = {"id": tm.id, "value": tm.new_value}

	# 2. Anything in the original grid not in moved_ids stays put. (Empty
	#    cells contribute id=0, which moved_ids never has, but we skip those.)
	for r in n:
		for c in n:
			var cell: Dictionary = _grid[r][c]
			var id: int = int(cell["id"])
			if id == 0:
				continue
			if not moved_ids.has(id):
				next_grid[r][c] = {"id": id, "value": int(cell["value"])}

	_grid = next_grid
	_score += p.gained_score
	_check_won()
	# Spawn a new tile in the now-vacated space.
	_spawn_random_tile()
	return true


## Convenience: plan(dir) + commit. Returns true iff state changed.
func apply(dir: int) -> bool:
	var p: Planner.MovePlan = plan(dir)
	return commit(p)


func is_won() -> bool:
	return _won


## True iff no legal move exists in any direction. A legal move = a non-empty
## plan in any one of the four directions. Equivalently (and more cheaply):
## any empty cell, OR any pair of adjacent equal-value cells.
func is_lost() -> bool:
	var n: int = config.size
	for r in n:
		for c in n:
			var v: int = int(_grid[r][c]["value"])
			if v == 0:
				return false
			# Right neighbour
			if c + 1 < n and int(_grid[r][c + 1]["value"]) == v:
				return false
			# Down neighbour
			if r + 1 < n and int(_grid[r + 1][c]["value"]) == v:
				return false
	return true


## Wire-format snapshot. Includes everything needed for round-trip restore:
## grid (with ids), score, won, rng seed-state, next_id. See docs/persistence.md.
func snapshot() -> Dictionary:
	var grid_out: Array = []
	for r in config.size:
		var row: Array = []
		for c in config.size:
			var cell: Dictionary = _grid[r][c]
			row.append({"id": int(cell["id"]), "value": int(cell["value"])})
		grid_out.append(row)
	return {
		"version": SCHEMA_VERSION,
		"grid": grid_out,
		"score": _score,
		"won": _won,
		"next_id": _next_id,
		"rng_state": _rng.state,
		"size": config.size,
		"target_value": config.target_value,
		"four_probability": config.four_probability,
	}


## Restore a state from a previously-captured snapshot. Round-trips via:
##   from_snapshot(s.snapshot()).snapshot() == s.snapshot()
static func from_snapshot(snap: Dictionary) -> Self:
	var s: Self = Self.new()
	s.config = Game2048Config.new()
	s.config.size = int(snap.get("size", 4))
	s.config.target_value = int(snap.get("target_value", 2048))
	s.config.four_probability = float(snap.get("four_probability", 0.1))
	s._rng = RandomNumberGenerator.new()
	# RNG state is opaque to us; just round-trip it.
	s._rng.state = int(snap["rng_state"])
	s._score = int(snap["score"])
	s._won = bool(snap["won"])
	s._next_id = int(snap["next_id"])
	# Rebuild grid; copy each cell so callers can't accidentally mutate the
	# snapshot dict and bleed state in.
	var grid_in: Array = snap["grid"]
	var n: int = s.config.size
	var g: Array = []
	for r in n:
		var row: Array = []
		for c in n:
			var cell: Dictionary = grid_in[r][c]
			row.append({"id": int(cell["id"]), "value": int(cell["value"])})
		g.append(row)
	s._grid = g
	return s


# --- Internals ---


func _check_won() -> void:
	if _won:
		return
	var t: int = config.target_value
	for r in config.size:
		for c in config.size:
			if int(_grid[r][c]["value"]) >= t:
				_won = true
				return


# Pick a uniformly-random empty cell. If none, no-op (caller should ensure
# at least one empty before calling, but for robustness this is a no-op
# rather than crash). Spawns 2 (P = 1 - four_probability) or 4.
func _spawn_random_tile() -> void:
	var empty: Array = []
	for r in config.size:
		for c in config.size:
			if int(_grid[r][c]["value"]) == 0:
				empty.append(Vector2i(c, r))
	if empty.is_empty():
		return
	var pick: Vector2i = empty[_rng.randi_range(0, empty.size() - 1)]
	var roll: float = _rng.randf()
	var v: int = 4 if roll < config.four_probability else 2
	_grid[pick.y][pick.x] = {"id": _next_id, "value": v}
	_next_id += 1
