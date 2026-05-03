extends RefCounted
## BreakoutGameState — pure ball/paddle/brick rules. No Node, no signals.
##
## Architecture:
##   - tick(now_ms) advances internal sim by integer-millisecond fixed
##     sub-steps of config.step_dt_ms (default 10), up to max_steps_per_tick.
##   - tick() returns bool: true iff anything visible changed this call
##     (per architecture rule: cores expose changes via return value +
##     snapshot diff, not signals).
##   - snapshot() returns a Dictionary with version=1 for round-trip and
##     scene-side diff detection.
##
## Coordinates: world origin top-left; +Y points DOWN. Ball falls below
## world_h → life lost.

const Self := preload("res://scripts/breakout/core/breakout_state.gd")
const BreakoutConfig := preload("res://scripts/breakout/core/breakout_config.gd")
const BreakoutLevel := preload("res://scripts/breakout/core/breakout_level.gd")
const Aabb := preload("res://scripts/breakout/core/aabb.gd")

const SCHEMA_VERSION: int = 1

enum Mode { STICKY = 0, LIVE = 1, WON = 2, LOST = 3 }

# --- Game state ---
var config: BreakoutConfig
var level: BreakoutLevel

var paddle_x: float = 0.0          # center x
var paddle_intent_vx: float = 0.0  # px/sec, set by caller, clamped at apply
var ball_x: float = 0.0
var ball_y: float = 0.0
var ball_vx: float = 0.0
var ball_vy: float = 0.0
var lives: int = 0
var score: int = 0
var mode: int = Mode.STICKY

# bricks: Array[Dictionary] each {idx, cx, cy, hx, hy, hp, value, destructible, color_id}.
# `idx` is preserved from level.cells for stable diffing in snapshot.
var bricks: Array = []

# Time bookkeeping. `last_tick_ms` is the last `now_ms` we caught up to.
# `accum_ms` is the leftover deficit < step_dt_ms.
var last_tick_ms: int = 0
var initialized_clock: bool = false
var accum_ms: int = 0

var _rng: RandomNumberGenerator


# --- Construction ---


static func create(game_seed: int, cfg: BreakoutConfig, lvl: BreakoutLevel) -> Self:
	# Tunneling cap (acceptance #9). The fastest a ball travels in one fixed
	# step is `ball_speed * step_dt_ms / 1000`. That distance must be smaller
	# than the smallest collidable feature so the ball can't skip over it.
	var step_dt_s: float = float(cfg.step_dt_ms) / 1000.0
	var max_step_dist: float = cfg.ball_speed_start * step_dt_s
	var min_feature: float = minf(lvl.brick_w, minf(lvl.brick_h, cfg.paddle_h))
	if max_step_dist >= min_feature:
		push_error("BreakoutGameState.create: tunneling cap violated — ball_speed * step_dt = %f >= min(brick_w=%f, brick_h=%f, paddle_h=%f) = %f. Reduce ball_speed_start or step_dt_ms." \
			% [max_step_dist, lvl.brick_w, lvl.brick_h, cfg.paddle_h, min_feature])
		assert(false, "tunneling cap violated")

	var s: Self = Self.new()
	s.config = cfg
	s.level = lvl
	s._rng = RandomNumberGenerator.new()
	s._rng.seed = game_seed
	s.lives = cfg.lives_start
	s.score = 0
	s.paddle_x = cfg.world_w * 0.5
	s.bricks = _expand_level_to_bricks(lvl)
	s.mode = Mode.STICKY
	s._reset_ball_to_sticky()
	# Degenerate level (no destructibles to clear): start already won.
	if s._all_destructibles_cleared():
		s.mode = Mode.WON
	return s


static func _expand_level_to_bricks(lvl: BreakoutLevel) -> Array:
	# Walks lvl.cells (flat row-major) and emits one brick record per
	# non-empty cell (hp > 0). Empty cells are skipped entirely; the
	# original flat index is preserved as `idx` so the scene can pin
	# render nodes to a stable id across snapshots.
	var out: Array = []
	var hx: float = lvl.brick_w * 0.5
	var hy: float = lvl.brick_h * 0.5
	var n: int = lvl.cells.size()
	for i in n:
		var cell: Variant = lvl.cells[i]
		if not (cell is Dictionary):
			continue
		var d: Dictionary = cell
		var hp: int = int(d.get("hp", 0))
		if hp <= 0:
			continue
		var col: int = i % lvl.cols
		var row: int = i / lvl.cols
		var cx: float = lvl.origin_x + col * lvl.brick_w + hx
		var cy: float = lvl.origin_y + row * lvl.brick_h + hy
		out.append({
			"idx": i,
			"cx": cx,
			"cy": cy,
			"hx": hx,
			"hy": hy,
			"hp": hp,
			"value": int(d.get("value", 100)),
			"destructible": bool(d.get("destructible", true)),
			"color_id": int(d.get("color_id", 0)),
		})
	return out


# --- Public API ---


func set_paddle_intent(velocity_x: float) -> void:
	# Clamp to ±max so the caller can't bypass speed limits with a huge intent.
	var m: float = config.paddle_max_speed_px_s
	paddle_intent_vx = clampf(velocity_x, -m, m)


func launch() -> void:
	# Leaves sticky mode — only takes effect if currently sticky AND game
	# hasn't ended. Random initial X-component within bias_max_x so the
	# ball doesn't always go straight up; deterministic from the rng.
	if mode != Mode.STICKY:
		return
	mode = Mode.LIVE
	var bias_t: float = _rng.randf_range(-config.bias_max_x, config.bias_max_x)
	var vx: float = bias_t * config.ball_speed_start
	var speed_sq: float = config.ball_speed_start * config.ball_speed_start
	var vy: float = -sqrt(maxf(speed_sq - vx * vx, 0.0))
	ball_vx = vx
	ball_vy = vy


## tick(now_ms): advance sim to `now_ms`. Returns true iff visible state
## changed. `now_ms` may move forward by any amount; we catch up in fixed
## sub-steps capped at config.max_steps_per_tick. On the very first call,
## we just align our clock and do no sub-steps (so a long delay before the
## first tick doesn't dump 100 sub-steps in one frame).
func tick(now_ms: int) -> bool:
	if not initialized_clock:
		last_tick_ms = now_ms
		initialized_clock = true
		return false
	var dt_ms: int = now_ms - last_tick_ms
	if dt_ms <= 0:
		return false
	last_tick_ms = now_ms
	accum_ms += dt_ms
	var changed: bool = false
	var steps: int = 0
	while accum_ms >= config.step_dt_ms and steps < config.max_steps_per_tick:
		accum_ms -= config.step_dt_ms
		if _step():
			changed = true
		steps += 1
	# If we hit the iteration cap with leftover time, drop it. Otherwise the
	# cap is meaningless. (Documented: a tab-out + return shouldn't unleash
	# 1000 steps of catch-up; the player resumes a "frozen" state.)
	if steps >= config.max_steps_per_tick and accum_ms >= config.step_dt_ms:
		accum_ms = 0
	return changed


func is_game_over() -> bool:
	return mode == Mode.LOST


func is_won() -> bool:
	return mode == Mode.WON


## Wire-format snapshot. Bricks are listed only with idx + hp + destroyed;
## a destroyed brick is kept around (hp=0, destroyed=true) for one frame so
## the scene can detect the destruction in its diff and play the FX, then
## be removed. Actually, simpler: we keep them in `bricks` but with hp=0,
## and the scene treats absence-from-snapshot as "destroyed". To make diffs
## crisp without scene state, we DROP destroyed bricks from snapshot.
func snapshot() -> Dictionary:
	var brick_out: Array = []
	for b in bricks:
		if int(b["hp"]) <= 0:
			continue
		brick_out.append({
			"idx": int(b["idx"]),
			"hp": int(b["hp"]),
		})
	return {
		"version": SCHEMA_VERSION,
		"paddle": {"x": paddle_x, "w": config.paddle_w, "h": config.paddle_h, "y": config.paddle_y},
		"ball": {"x": ball_x, "y": ball_y, "vx": ball_vx, "vy": ball_vy, "r": config.ball_radius},
		"bricks": brick_out,
		"lives": lives,
		"score": score,
		"mode": mode,
		"last_tick_ms": last_tick_ms,
	}


# --- Internals ---


# One fixed sub-step (config.step_dt_ms). Returns true iff any visible
# field changed. "Visible" includes paddle movement, ball movement, brick
# hp change, life loss, mode change.
func _step() -> bool:
	var dt: float = float(config.step_dt_ms) / 1000.0
	var changed: bool = false

	# 1. Paddle motion.
	if paddle_intent_vx != 0.0:
		var new_paddle_x: float = paddle_x + paddle_intent_vx * dt
		var phx: float = config.paddle_w * 0.5
		new_paddle_x = clampf(new_paddle_x, phx, config.world_w - phx)
		if not is_equal_approx(new_paddle_x, paddle_x):
			paddle_x = new_paddle_x
			changed = true

	# In sticky mode, ball follows the paddle and ignores walls/bricks.
	if mode == Mode.STICKY:
		var prev_bx: float = ball_x
		ball_x = paddle_x
		ball_y = config.paddle_y - config.ball_radius - 0.001
		if not is_equal_approx(prev_bx, ball_x):
			changed = true
		return changed

	if mode == Mode.WON or mode == Mode.LOST:
		return changed

	# 2. Ball motion.
	ball_x += ball_vx * dt
	ball_y += ball_vy * dt
	changed = true

	# 3. Walls. Reflect on left/right/top; bottom = life loss (handled #6).
	var br: float = config.ball_radius
	if ball_x - br < 0.0 and ball_vx < 0.0:
		ball_x = br
		ball_vx = -ball_vx
	elif ball_x + br > config.world_w and ball_vx > 0.0:
		ball_x = config.world_w - br
		ball_vx = -ball_vx
	if ball_y - br < 0.0 and ball_vy < 0.0:
		ball_y = br
		ball_vy = -ball_vy

	# 4. Paddle collision (only if descending, so the ball can't latch onto
	# the paddle's underside).
	if ball_vy > 0.0:
		var phx2: float = config.paddle_w * 0.5
		var phy: float = config.paddle_h * 0.5
		var pcx: float = paddle_x
		var pcy: float = config.paddle_y + phy
		if Aabb.overlaps(ball_x, ball_y, br, br, pcx, pcy, phx2, phy):
			# Resolve to top of paddle and apply piecewise-linear x-bias.
			ball_y = pcy - phy - br - 0.001
			var bias_t: float = clampf((ball_x - pcx) / phx2, -1.0, 1.0) * config.bias_max_x
			var speed: float = config.ball_speed_start
			var new_vx: float = bias_t * speed
			var new_vy_sq: float = speed * speed - new_vx * new_vx
			ball_vx = new_vx
			ball_vy = -sqrt(maxf(new_vy_sq, 0.0))

	# 5. Bricks. Find ALL overlapping bricks; pick the one to decrement per
	# acceptance #5: largest dominant-axis penetration; ties → lower idx.
	# Reflect on that brick's dominant axis. Other overlapping bricks are
	# left untouched (intentional Breakout feel).
	var hits: Array = []   # [{i, depth: {x,y}, axis: "x"|"y"|"tie"}]
	for i in bricks.size():
		var b: Dictionary = bricks[i]
		if int(b["hp"]) <= 0:
			continue
		if not Aabb.overlaps(ball_x, ball_y, br, br,
				float(b["cx"]), float(b["cy"]), float(b["hx"]), float(b["hy"])):
			continue
		var d: Dictionary = Aabb.overlap_depths(ball_x, ball_y, br, br,
			float(b["cx"]), float(b["cy"]), float(b["hx"]), float(b["hy"]))
		hits.append({"i": i, "depth": d})

	if not hits.is_empty():
		# Pick the winner per acceptance #5: largest dominant-axis depth wins;
		# ties → lower idx. Dominant axis = the SMALLER of (depth_x, depth_y),
		# i.e. the axis the ball just barely crossed.
		var winner: int = -1
		var winner_depth: float = -1.0
		var winner_axis: String = "x"
		for h in hits:
			var dpt: Dictionary = h["depth"]
			var dxv: float = float(dpt["x"])
			var dyv: float = float(dpt["y"])
			# Dominant axis = smaller depth (the axis we just barely crossed).
			# Ties → "X wins" per the documented rule.
			var axis: String
			var axis_depth: float
			if dxv <= dyv:
				axis = "x"
				axis_depth = dxv
			else:
				axis = "y"
				axis_depth = dyv
			if axis_depth > winner_depth:
				winner = int(h["i"])
				winner_depth = axis_depth
				winner_axis = axis
			# Defensive against future iteration-order changes: lower idx wins
			# on dominant-axis tie. Unreachable today (hits is built in
			# increasing index order so the first equal-depth hit already
			# holds the lowest idx) but kept so the rule survives a refactor.
			elif is_equal_approx(axis_depth, winner_depth) and int(h["i"]) < winner:
				winner = int(h["i"])
				winner_axis = axis

		# Reflect ball on winner_axis; resolve penetration.
		var b2: Dictionary = bricks[winner]
		var bcx: float = float(b2["cx"])
		var bcy: float = float(b2["cy"])
		var bhx: float = float(b2["hx"])
		var bhy: float = float(b2["hy"])
		if winner_axis == "x":
			# Reflect X. Push out of the brick on the X axis.
			if ball_x < bcx:
				ball_x = bcx - bhx - br - 0.001
			else:
				ball_x = bcx + bhx + br + 0.001
			ball_vx = -ball_vx
		else:
			if ball_y < bcy:
				ball_y = bcy - bhy - br - 0.001
			else:
				ball_y = bcy + bhy + br + 0.001
			ball_vy = -ball_vy

		# Decrement brick hp — but ONLY if destructible. Indestructible bricks
		# reflect the ball forever and are never removed from collision.
		if bool(b2["destructible"]):
			var new_hp: int = int(b2["hp"]) - 1
			b2["hp"] = new_hp
			if new_hp <= 0:
				score += int(b2["value"])
		bricks[winner] = b2

		# Check win condition: any destructible bricks left?
		if _all_destructibles_cleared():
			mode = Mode.WON

	# 6. Life loss: ball below world.
	if ball_y - br > config.world_h:
		lives -= 1
		if lives <= 0:
			mode = Mode.LOST
		else:
			mode = Mode.STICKY
			_reset_ball_to_sticky()

	return changed


func _all_destructibles_cleared() -> bool:
	for b in bricks:
		if bool(b["destructible"]) and int(b["hp"]) > 0:
			return false
	return true


# Reset ball to sticky position above paddle, velocity zero.
func _reset_ball_to_sticky() -> void:
	ball_x = paddle_x
	ball_y = config.paddle_y - config.ball_radius - 0.001
	ball_vx = 0.0
	ball_vy = 0.0
