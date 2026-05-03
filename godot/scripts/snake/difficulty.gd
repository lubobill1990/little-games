extends RefCounted
## Snake difficulty buckets. Pure data — no Node, no signals.
##
## Each bucket maps to a (start_step_ms, walls) pair plus a stable id used as
## the persistence-key suffix (`snake.best.<id>`, see docs/persistence.md).
## `last_difficulty` is the most-recently-picked id, restored on scene re-entry.

const DIFFICULTIES: Array = [
	{"id": "easy",   "title": "Easy",   "start_step_ms": 180, "walls": false},
	{"id": "normal", "title": "Normal", "start_step_ms": 130, "walls": true},
	{"id": "hard",   "title": "Hard",   "start_step_ms":  90, "walls": true},
]

const DEFAULT_ID: String = "normal"
const LAST_KEY: StringName = &"snake.last_difficulty"


static func ids() -> Array:
	var out: Array = []
	for d in DIFFICULTIES:
		out.append(String(d["id"]))
	return out


static func by_id(id: String) -> Dictionary:
	for d in DIFFICULTIES:
		if String(d["id"]) == id:
			return d
	return by_id(DEFAULT_ID)


## Persistence key for a difficulty's best score: `snake.best.<id>`.
static func best_key(id: String) -> StringName:
	return StringName("snake.best.%s" % id)
