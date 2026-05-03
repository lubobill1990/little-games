extends RefCounted
## Static helpers for Galaga-style dive attacks (#30).
##
## Pure math + RNG — no Node, no signals. Lives in `core/` so it's
## unit-testable without a SceneTree. Owned by `invaders_state.gd`, which
## holds the live `divers` array and routes dive ticks here.
##
## A diver is a Dictionary with keys:
##   row, col            : int — original formation slot (for return + scoring)
##   p0, p1, p2          : Vector2 — quadratic Bezier control points (world coords)
##   t                   : float — 0..1 path parameter
##   speed               : float — t advancement per second
##   fire_checkpoints    : PackedFloat32Array — pending fire-t values (sorted asc)
##   mode                : int — MODE_DIVING | MODE_RETURNING | MODE_KAMIKAZE

const MODE_DIVING: int = 0     # one-way dive (flies past playfield bottom)
const MODE_RETURNING: int = 1  # arcs out then loops back to formation slot
const MODE_KAMIKAZE: int = 2   # tracks toward player; counts as a hit on contact

# Mode probabilities. Sums to 1.0.
const P_RETURNING: float = 0.7
const P_KAMIKAZE: float = 0.3   # implied: 1.0 - P_RETURNING

# Fire checkpoints inside a single dive path (in t-units).
const FIRE_CHECKPOINTS: Array = [0.3, 0.7]


# --- Bezier ---


## Quadratic Bezier evaluation. B(t) = (1-t)²·p0 + 2(1-t)t·p1 + t²·p2.
static func bezier_eval(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return (u * u) * p0 + (2.0 * u * t) * p1 + (t * t) * p2


## Tangent of the quadratic Bezier at t. B'(t) = 2(1-t)(p1-p0) + 2t(p2-p1).
## Useful for sprite rotation along the path.
static func bezier_tangent(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return (2.0 * u) * (p1 - p0) + (2.0 * t) * (p2 - p1)


# --- Trigger / cap ---


## Per-wave dive probability (per dive_check tick). Caps at ~0.6 to avoid
## monotony at high waves. wave 1 is too early for dives; returns 0.
static func dive_probability(wave: int) -> float:
	if wave < 2:
		return 0.0
	# Linear ramp from 0.15 at wave 2 to 0.6 at wave 8+.
	var w: float = clampf(float(wave), 2.0, 8.0)
	return lerpf(0.15, 0.6, (w - 2.0) / 6.0)


## Per-wave cap on simultaneous active divers. Wave 1: 0. Wave 2: 1. Linear
## ramp to 4 at wave 8+. Conservative — keeps the screen readable.
static func max_active_dives(wave: int) -> int:
	if wave < 2:
		return 0
	var w: int = clampi(wave, 2, 8)
	# 1, 1, 2, 2, 3, 3, 4 across waves 2..8.
	return clampi((w - 2) / 2 + 1, 1, 4)


## Decide whether to attempt a dive on this check tick. Returns true if all
## three gates pass: cooldown elapsed, RNG, and headroom under the wave cap.
## Caller still needs to *find* a divable enemy — should_dive only gates the
## *attempt*, not the success.
static func should_dive(rng: RandomNumberGenerator, wave: int, now_ms: int,
		last_check_ms: int, dive_check_ms: int, active_dives: int) -> bool:
	if wave < 2:
		return false
	if (now_ms - last_check_ms) < dive_check_ms:
		return false
	if active_dives >= max_active_dives(wave):
		return false
	return rng.randf() < dive_probability(wave)


## Pick the mode for a new dive (Returning vs Kamikaze). Diving is the
## inflight state, never picked at start.
static func pick_mode(rng: RandomNumberGenerator) -> int:
	return MODE_RETURNING if rng.randf() < P_RETURNING else MODE_KAMIKAZE


# --- Path construction ---


## Build a quadratic Bezier path from the diver's current world position to
## either (a) the kamikaze target near the player, or (b) a re-entry curve
## ending back at slot_pos. Returns Dictionary {p0, p1, p2}.
##
## `world_w/world_h` are the playfield dims; we use them to keep the curve
## visually inside the screen. `player_x` is where the player is *now* —
## sampling once at dive start gives a "lead" feel without continuous
## tracking.
static func sample_dive_path(rng: RandomNumberGenerator, mode: int,
		current_pos: Vector2, slot_pos: Vector2, player_x: float,
		world_w: float, world_h: float) -> Dictionary:
	var p0: Vector2 = current_pos
	var p1: Vector2
	var p2: Vector2
	if mode == MODE_KAMIKAZE:
		# Swing slightly outward, then dive at the player's last-known x.
		var swing_x: float = current_pos.x + (rng.randf() - 0.5) * world_w * 0.4
		swing_x = clampf(swing_x, 8.0, world_w - 8.0)
		var swing_y: float = current_pos.y + world_h * 0.3
		p1 = Vector2(swing_x, swing_y)
		p2 = Vector2(clampf(player_x, 0.0, world_w), world_h + 8.0)
	else:
		# Returning: arc out (one side picked by RNG), loop back to slot_pos.
		var side: float = 1.0 if rng.randf() < 0.5 else -1.0
		var arc_x: float = clampf(current_pos.x + side * world_w * 0.35,
				8.0, world_w - 8.0)
		var arc_y: float = current_pos.y + world_h * 0.45
		p1 = Vector2(arc_x, arc_y)
		p2 = slot_pos
	return {"p0": p0, "p1": p1, "p2": p2}


## Construct a fresh diver dict. `speed` is t/sec; default 0.5 means a 2 s
## traversal of the path.
static func make_diver(row: int, col: int, path: Dictionary, mode: int,
		speed: float = 0.5) -> Dictionary:
	var fire_cps: PackedFloat32Array = PackedFloat32Array()
	for cp in FIRE_CHECKPOINTS:
		fire_cps.append(float(cp))
	return {
		"row": row,
		"col": col,
		"p0": path["p0"],
		"p1": path["p1"],
		"p2": path["p2"],
		"t": 0.0,
		"speed": speed,
		"fire_checkpoints": fire_cps,
		"mode": mode,
	}


# --- Tracking bullet velocity ---


## Velocity vector for an enemy bullet fired by a diver, aimed (with no lead)
## at `target_x` along the player's row. Returns a Vector2 (px/sec).
static func tracker_velocity(diver_pos: Vector2, target_x: float,
		player_y: float, bullet_speed: float) -> Vector2:
	var dx: float = target_x - diver_pos.x
	var dy: float = player_y - diver_pos.y
	if dy <= 0.0:
		# Player is above the diver (shouldn't happen mid-dive, but be safe).
		return Vector2(0.0, bullet_speed)
	var len: float = sqrt(dx * dx + dy * dy)
	if len < 1e-6:
		return Vector2(0.0, bullet_speed)
	return Vector2(dx / len * bullet_speed, dy / len * bullet_speed)
