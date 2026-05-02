class_name TetrisLevels
extends RefCounted
## Gravity ms-per-row by level (Tetris Worlds curve, the most-cited Guideline
## reference). Pure data. Levels >= MAX_LEVEL are clamped to the fastest tier.
##
## Source: https://tetris.wiki/Tetris_Worlds#Gravity
## Formula: ((0.8 - ((level - 1) * 0.007)) ^ (level - 1)) seconds per row.
##
## We pre-compute integer milliseconds at module load time so tick() never
## touches floats. The table is monotonically decreasing in ms / level.

const MAX_LEVEL: int = 20

# Pre-computed table; index = level - 1 (so level 1 → ms_per_row[0]).
const _MS_PER_ROW: Array = [
	1000,  # L1
	793,   # L2
	618,   # L3
	473,   # L4
	355,   # L5
	262,   # L6
	190,   # L7
	135,   # L8
	94,    # L9
	64,    # L10
	43,    # L11
	28,    # L12
	18,    # L13
	11,    # L14
	7,     # L15
	4,     # L16
	3,     # L17
	2,     # L18
	1,     # L19
	1,     # L20+
]

static func ms_per_row(level: int) -> int:
	if level < 1:
		return _MS_PER_ROW[0]
	if level >= MAX_LEVEL:
		return _MS_PER_ROW[MAX_LEVEL - 1]
	return _MS_PER_ROW[level - 1]
