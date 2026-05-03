extends RefCounted
## sub_rng.gd — deterministic RNG fan-out for tank.
##
## Each consumer (spawn, AI target, AI fire, drops, level-pick, etc.) gets
## its own RandomNumberGenerator seeded from `master_seed XOR tag`. This
## keeps streams independent: adding a new sub-RNG can never perturb the
## sequences observed by existing consumers, which is the whole point —
## determinism stays stable across feature additions.
##
## Tag IDs are listed below as constants. NEVER reuse a tag value for a
## different consumer (would cause two streams to be byte-identical and
## couple their behavior); NEVER renumber an existing tag (would change
## historic seeds and break replay determinism).

const Self := preload("res://scripts/tank/core/sub_rng.gd")

# Tag table — mirrors invaders/state's one-liner XOR pattern but with a
# named per-consumer enum so future readers can tell which stream is which.
const TAG_SPAWN: int = 0x5350_4E_01     # enemy spawn jitter / kind selection
const TAG_AI_TARGET: int = 0x5441_5247  # AI per-tank target switch (Bayes coin)
const TAG_AI_FIRE: int = 0x4149_4655    # AI per-tank fire decision
const TAG_DROP: int = 0x4452_4F50       # power-up drop placement
const TAG_PICK: int = 0x5049_434B       # roster bonus marker → power-up kind


## Build a sub-RNG seeded from `master_seed XOR tag`. Caller is
## TankGameState.create() (one per consumer at game start). Returns a
## fresh RandomNumberGenerator — caller stores it.
static func make(master_seed: int, tag: int) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = master_seed ^ tag
	return r
