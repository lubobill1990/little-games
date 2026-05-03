extends RefCounted
## ai.gd — pure stateless decision functions for enemy tanks. No Node, no
## Engine APIs, no global state — all RNG state lives in the caller's
## `RandomNumberGenerator` instances so determinism is byte-stable across
## snapshot-restore.
##
## Behavior model (FC-faithful for v1):
##   - Every `cfg.ai_recheck_ms`, the enemy decides a new direction:
##       * with probability `cfg.ai_p_target_base`, pick a direction biased
##         toward the base (one of the two cardinal axes that reduces
##         |delta| toward base_pos);
##       * otherwise, pick uniformly at random from {N, E, S, W}.
##     Between recheck windows, the enemy keeps its current direction.
##   - Every sub-step (independent of recheck), with probability
##     `cfg.ai_p_fire`, fire.
##
## Deterministic-replay contract: the only RNG draws are
##   - one `randf()` from `target_rng` per recheck (target-vs-random gate),
##   - one `randi()` from `target_rng` per recheck only when the random
##     branch is taken (direction pick),
##   - one `randf()` from `fire_rng` per sub-step per live enemy.
## Adding a future consumer must use a NEW sub-RNG tag, not perturb these.

const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")


## Pick a direction for `enemy` at time `now_ms`. Returns -1 when no
## decision is due (recheck window not elapsed); the caller should keep
## the enemy's current `facing`.
##
## `enemy["last_decision_ms"]` is mutated when a decision IS made so the
## next call honors `ai_recheck_ms`.
static func decide_dir(target_rng: RandomNumberGenerator, enemy: Dictionary,
		base_pos: Array, cfg: TankConfig, now_ms: int) -> int:
	if not enemy["alive"]:
		return -1
	var last: int = int(enemy["last_decision_ms"])
	if now_ms - last < cfg.ai_recheck_ms:
		return -1
	enemy["last_decision_ms"] = now_ms
	# Gate: random vs. base-target.
	var roll: float = target_rng.randf()
	if roll < cfg.ai_p_target_base and base_pos.size() == 2:
		return _dir_toward_base(enemy, base_pos, cfg)
	# Random direction in 0..3. randi() % 4 is biased over a 32-bit window
	# only by 2^-30 — negligible for AI and keeps the draw count to 1.
	return int(target_rng.randi() % 4)


## Roll the per-sub-step fire probability. Returns true iff the enemy
## should attempt to fire this sub-step. Caller is responsible for
## enforcing cooldown / max-bullets-on-screen.
static func should_fire(fire_rng: RandomNumberGenerator, cfg: TankConfig) -> bool:
	return fire_rng.randf() < cfg.ai_p_fire


# --- internal ---

## Pick the cardinal direction that reduces the larger axis-distance from
## the enemy center to the base center. Ties (|dx| == |dy|) break toward
## the vertical axis, matching the FC bias toward "go down toward base".
static func _dir_toward_base(enemy: Dictionary, base_pos: Array, cfg: TankConfig) -> int:
	var bcx: int = (int(base_pos[0])) * cfg.tile_size_sub + cfg.tile_size_sub / 2
	var bcy: int = (int(base_pos[1])) * cfg.tile_size_sub + cfg.tile_size_sub / 2
	var dx: int = bcx - int(enemy["x"])
	var dy: int = bcy - int(enemy["y"])
	if absi(dy) >= absi(dx):
		return TileGrid.DIR_S if dy > 0 else TileGrid.DIR_N
	return TileGrid.DIR_E if dx > 0 else TileGrid.DIR_W
