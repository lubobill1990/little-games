extends RefCounted
## ufo.gd — pure helpers for the UFO bonus saucer. State (alive flag,
## position, direction, last-spawn timestamp) lives in InvadersGameState;
## these are stateless functions.
##
## Score table is the deterministic [50,100,150,300] (Dev plan §UFO).
## Picked by `_ufo_rng.randi() % 4` so it is reproducible from the seed.

const SCORE_TABLE: Array = [50, 100, 150, 300]


## Should we spawn a UFO right now? Called once per fixed sub-step.
## Spawns iff:
##   - No UFO is currently alive (caller's responsibility to check).
##   - Time since the last spawn (or game start) ≥ ufo_interval_ms +
##     jitter, where jitter ∈ [-half, +half] drawn from `rng`.
static func should_spawn(rng: RandomNumberGenerator, now_ms: int,
		last_spawn_ms: int, interval_ms: int, jitter_ms: int) -> bool:
	# Jitter: uniform integer in [-jitter_ms/2, +jitter_ms/2].
	var jitter: int = (rng.randi() % (jitter_ms + 1)) - (jitter_ms / 2)
	return now_ms - last_spawn_ms >= interval_ms + jitter


## Pick the score awarded for hitting the UFO. Indexed by `rng.randi() % 4`.
static func pick_score(rng: RandomNumberGenerator) -> int:
	return SCORE_TABLE[rng.randi() % SCORE_TABLE.size()]


## Pick spawn direction: -1 (right→left, spawned at right edge) or +1
## (left→right, spawned at left edge). Selected by low bit of an rng draw.
static func pick_direction(rng: RandomNumberGenerator) -> int:
	return -1 if (rng.randi() & 1) == 1 else 1
