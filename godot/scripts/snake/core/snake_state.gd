extends RefCounted
## SnakeGameState — the pure Snake rules engine.
##
## Pure: no Node, no Engine, no signals. Caller drives time via tick(now_ms)
## and feeds intent via turn(dir). Per architecture.md "Snapshot diffs, not
## signals", state changes are surfaced through tick()'s bool return + the
## snapshot() Dictionary.
##
## Determinism contract: same seed + same SnakeConfig + same input timeline
## produces the same snapshot stream, byte-for-byte. Tests rely on this.

const Self := preload("res://scripts/snake/core/snake_state.gd")
const SnakeConfig := preload("res://scripts/snake/core/snake_config.gd")
const SnakeRng := preload("res://scripts/snake/core/snake_rng.gd")

const SCHEMA_VERSION: int = 1

enum Dir { UP = 0, RIGHT = 1, DOWN = 2, LEFT = 3 }

const _DIR_VEC: Array[Vector2i] = [
	Vector2i(0, -1),  # UP
	Vector2i(1, 0),   # RIGHT
	Vector2i(0, 1),   # DOWN
	Vector2i(-1, 0),  # LEFT
]

var config: SnakeConfig
var _rng: SnakeRng
var _snake: Array[Vector2i] = []  # head at index 0; ordered head → tail
var _dir: int = Dir.RIGHT
var _pending_dir: int = -1        # buffered turn for next tick; -1 = none
var _food: Vector2i = Vector2i.ZERO
var _score: int = 0
var _level: int = 1
var _foods_eaten: int = 0
var _step_ms: int = 0
var _last_tick_ms: int = -1
var _game_over: bool = false


static func create(game_seed: int, cfg: SnakeConfig) -> Self:
	var s: Self = Self.new()
	s.config = cfg
	s._rng = SnakeRng.create(game_seed)
	s._step_ms = cfg.start_step_ms
	# Seed snake at center, length 3, facing RIGHT.
	var cx: int = cfg.grid_w / 2
	var cy: int = cfg.grid_h / 2
	s._snake = [
		Vector2i(cx, cy),
		Vector2i(cx - 1, cy),
		Vector2i(cx - 2, cy),
	]
	s._dir = Dir.RIGHT
	s._food = s._spawn_food()
	return s


# --- Public API ---


## Buffer one turn. Rejects 180° instant reverses. Buffer is single-slot:
## a second call before the next tick OVERWRITES nothing — first wins. Rationale:
## acceptance #2 ("two turn calls within one tick → only the first applies").
func turn(dir: int) -> void:
	if _game_over:
		return
	if dir < 0 or dir >= 4:
		return
	if _pending_dir != -1:
		return  # buffer already full; second press dropped
	if _is_opposite(dir, _dir):
		return
	_pending_dir = dir


## Advance the simulation up to `max_steps_per_tick` steps. Returns true if
## any visible state changed (snake moved / score / game_over). Scene gates
## redraw on this; otherwise repaints are wasted work.
func tick(now_ms: int) -> bool:
	if _game_over:
		_last_tick_ms = now_ms
		return false
	if _last_tick_ms < 0:
		_last_tick_ms = now_ms
		return false
	var changed: bool = false
	var steps: int = 0
	var cap: int = max(1, config.max_steps_per_tick)
	while not _game_over and steps < cap and now_ms - _last_tick_ms >= _step_ms:
		_advance_one_step()
		_last_tick_ms += _step_ms
		steps += 1
		changed = true
	# If we hit the cap with time still pending, fast-forward _last_tick_ms so
	# the next tick() doesn't try to catch up another N steps. Otherwise a
	# 10-second background pause would game-over the snake instantly on resume.
	if steps >= cap and now_ms - _last_tick_ms >= _step_ms:
		_last_tick_ms = now_ms
	return changed


## Shift internal time origin so the next tick() sees a fresh delta. Used by
## the scene after a pause / focus-loss to avoid the catch-up storm above.
func set_last_tick(now_ms: int) -> void:
	_last_tick_ms = now_ms


func is_game_over() -> bool:
	return _game_over


## Wire-format snapshot. Scene diffs this between ticks for rendering;
## persistence stores a subset (typically version + score for high-score).
## See docs/persistence.md.
func snapshot() -> Dictionary:
	var snake_out: Array = []
	for cell in _snake:
		snake_out.append([cell.x, cell.y])
	return {
		"version": SCHEMA_VERSION,
		"snake": snake_out,
		"food": [_food.x, _food.y],
		"score": _score,
		"level": _level,
		"step_ms": _step_ms,
		"dir": _dir,
		"game_over": _game_over,
	}


# --- Internals ---


func _is_opposite(a: int, b: int) -> bool:
	return (a == Dir.UP and b == Dir.DOWN) \
		or (a == Dir.DOWN and b == Dir.UP) \
		or (a == Dir.LEFT and b == Dir.RIGHT) \
		or (a == Dir.RIGHT and b == Dir.LEFT)


func _advance_one_step() -> void:
	# 1. Apply buffered turn (already validated in turn()).
	if _pending_dir != -1:
		_dir = _pending_dir
		_pending_dir = -1

	# 2. Compute new head.
	var head: Vector2i = _snake[0]
	var new_head: Vector2i = head + _DIR_VEC[_dir]

	# 3. Wall / wrap.
	if config.walls:
		if new_head.x < 0 or new_head.x >= config.grid_w \
				or new_head.y < 0 or new_head.y >= config.grid_h:
			_game_over = true
			return
	else:
		new_head.x = posmod(new_head.x, config.grid_w)
		new_head.y = posmod(new_head.y, config.grid_h)

	# 4. Will-eat.
	var eat: bool = (new_head == _food)

	# 5. Self-collision. The tail vacates this tick iff we did NOT eat;
	#    so when not eating, exclude the tail cell from the obstacle set.
	#    Acceptance #8: tail-vacate is legal (no eat).
	var n: int = _snake.size()
	var collide_end: int = n if eat else n - 1
	for i in range(0, collide_end):
		if _snake[i] == new_head:
			_game_over = true
			return

	# 6. Move. Insert head; pop tail unless eating.
	_snake.insert(0, new_head)
	if eat:
		_score += 1
		_foods_eaten += 1
		if _foods_eaten % config.level_every == 0:
			_level += 1
			_step_ms = max(config.min_step_ms, int(round(_step_ms * config.level_factor)))
		# Respawn food. If the snake fills the entire board, no empty cells
		# remain — treat as a clean win-ish termination (game_over with no food).
		var next_food: Vector2i = _spawn_food()
		if next_food.x < 0:
			_game_over = true
			return
		_food = next_food
	else:
		_snake.pop_back()


## Pick a uniformly-random empty cell. Returns Vector2i(-1, -1) if the board
## is full (snake covers every cell) — caller treats as terminal.
func _spawn_food() -> Vector2i:
	var occupied: Dictionary = {}
	for cell in _snake:
		occupied[cell] = true
	var empty: Array[Vector2i] = []
	for y in config.grid_h:
		for x in config.grid_w:
			var c := Vector2i(x, y)
			if not occupied.has(c):
				empty.append(c)
	if empty.is_empty():
		return Vector2i(-1, -1)
	return empty[_rng.randi_below(empty.size())]
