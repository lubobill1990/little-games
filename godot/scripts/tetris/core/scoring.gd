extends RefCounted
## Tetris Guideline scoring: per-clear base, B2B (1.5x for difficult clears),
## combo bonus, and soft/hard-drop helpers. Pure stateful object — no Engine.
##
## Source: https://tetris.wiki/Scoring (Tetris Guideline column).
##
## Usage: call register_lock(rows_cleared, t_spin) after each piece locks
## (including locks that clear 0 rows — those reset the combo). soft_drop_cells
## and hard_drop_cells are added when the caller drops the piece.

const TSpin := preload("res://scripts/tetris/core/t_spin.gd")

var score: int = 0
var level: int = 1
var lines: int = 0
var combo: int = -1            # -1 = no combo active; first clear sets to 0
var b2b: int = -1              # -1 = no B2B; first difficult clear sets to 0
var perfect_clear_count: int = 0

# Base points per (t_spin, rows_cleared). Values are pre-level-multiplied.
const _BASE: Dictionary = {
	# t_spin = NONE
	0: { 0: 0, 1: 100, 2: 300, 3: 500, 4: 800 },
	# t_spin = MINI: 100, 200, 400 for 0,1,2 lines (3+ rows is unreachable for mini).
	1: { 0: 100, 1: 200, 2: 400 },
	# t_spin = FULL: 400, 800, 1200, 1600 for 0..3 lines.
	2: { 0: 400, 1: 800, 2: 1200, 3: 1600 },
}

# Whether a (t_spin, rows) combination is "difficult" for B2B purposes.
# Tetris (4 rows, no t-spin) and any T-spin that clears >=1 row are difficult.
static func _is_difficult(t_spin: int, rows: int) -> bool:
	if t_spin == TSpin.NONE:
		return rows == 4
	# T-spin (mini or full) with at least one line cleared = difficult.
	return rows >= 1

## Register a lock event. Returns the points added (after level multiplier &
## B2B bonus, before perfect-clear). Caller is expected to handle perfect-clear
## via register_perfect_clear() if its line-clear engine detected one.
func register_lock(rows: int, t_spin: int) -> int:
	# Combo bookkeeping: any clear extends the combo; a 0-row lock breaks it.
	var combo_added: int = 0
	if rows > 0:
		combo += 1
		if combo > 0:
			combo_added = 50 * combo * level
	else:
		combo = -1

	var base: int = int(_BASE[t_spin].get(rows, 0))
	var lock_points: int = base * level

	# B2B applies to difficult clears (Tetris or T-spin with lines).
	var difficult: bool = _is_difficult(t_spin, rows)
	if difficult and rows > 0:
		if b2b >= 0:
			# Already in B2B chain → 1.5x multiplier on the level-scaled base.
			lock_points = (lock_points * 3) / 2
		b2b += 1
	elif rows > 0:
		# Non-difficult clear breaks B2B.
		b2b = -1

	var added: int = lock_points + combo_added
	score += added
	lines += rows
	# Standard level curve: every 10 lines bumps the level. Caller can override
	# by writing to `level` directly between locks if a different progression is
	# desired (e.g., menu-selected start level).
	level = max(1, 1 + lines / 10)
	return added

## Add a perfect-clear bonus on top of the most recent lock. Per Guideline:
## single 800, double 1200, triple 1800, tetris 2000 (B2B-tetris perfect-clear
## is 3200 — caller passes b2b=true to apply the multiplier).
func register_perfect_clear(rows: int, b2b_active: bool) -> int:
	var bonus: int
	match rows:
		1: bonus = 800
		2: bonus = 1200
		3: bonus = 1800
		4: bonus = 2000
		_: bonus = 0
	bonus *= level
	if b2b_active and rows == 4:
		bonus = (bonus * 8) / 5  # 3200/2000 = 8/5 — keep integer math.
	score += bonus
	perfect_clear_count += 1
	return bonus

func add_soft_drop(cells: int) -> int:
	var pts: int = max(0, cells)
	score += pts
	return pts

func add_hard_drop(cells: int) -> int:
	var pts: int = 2 * max(0, cells)
	score += pts
	return pts

func reset() -> void:
	score = 0
	level = 1
	lines = 0
	combo = -1
	b2b = -1
	perfect_clear_count = 0
