extends RefCounted
## Tiny seeded RNG wrapper around Godot's RandomNumberGenerator. Pure: no
## global state, no Engine timing. Centralized so snake_state.gd doesn't
## leak the underlying type — if Godot's RNG ever drifts across versions we
## can swap to a hand-rolled xorshift here without touching callers.

const Self := preload("res://scripts/snake/core/snake_rng.gd")

var _rng: RandomNumberGenerator

static func create(rng_seed: int) -> Self:
	var r: Self = Self.new()
	r._rng = RandomNumberGenerator.new()
	r._rng.seed = rng_seed
	return r

## Uniformly pick an integer in [0, n). Caller must ensure n > 0.
func randi_below(n: int) -> int:
	return _rng.randi_range(0, n - 1)
