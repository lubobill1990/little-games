extends RefCounted
## Breakout level pack — ordered list of level resource paths. Source of
## truth for `breakout.gd`'s "advance on win" logic and persistence keys
## (`breakout.best.level_NN`).
##
## v1 ships levels 01–03; levels 04–05 + final credits screen land in the
## follow-up issue. Adding a new level requires:
##   1. Author `levels/level_NN.tres`.
##   2. Append its path to PACK in order.
##   3. Update docs/persistence.md's `breakout.best.level_NN` row.

const PACK: Array[String] = [
	"res://scenes/breakout/levels/level_01.tres",
	"res://scenes/breakout/levels/level_02.tres",
	"res://scenes/breakout/levels/level_03.tres",
]


## 1-based level index → resource path. Returns "" for out-of-range.
static func path_for(level_index: int) -> String:
	if level_index < 1 or level_index > PACK.size():
		return ""
	return PACK[level_index - 1]


static func size() -> int:
	return PACK.size()


## 1-based level index → "level_01" / "level_02" / … (zero-padded two-digit
## suffix per docs/persistence.md key namespace).
static func key_for(level_index: int) -> StringName:
	return StringName("breakout.best.level_%02d" % level_index)
