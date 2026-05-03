extends Resource
## Invaders level — per-row enemy kind + value table, plus the canonical
## bunker stamp. Pure data record, no Node.
##
## Rows are top-down: row 0 is the top row of the formation (worth more).
## `row_kinds[r]` returns a kind id; `row_values[r]` returns score awarded
## when that row's enemy is destroyed.
##
## The bunker stamp is one canonical pattern; `InvadersGameState.create()`
## replicates it `config.bunker_count` times across the bunker row.

# kind ids: 0 = bottom row (squid 10), 1 = mid rows (crab 20), 2 = top (octopus 30)
@export var row_kinds: PackedByteArray = PackedByteArray([2, 1, 1, 0, 0])
@export var row_values: PackedInt32Array = PackedInt32Array([30, 20, 20, 10, 10])

# Canonical bunker grid (1 = filled, 0 = empty). Row-major.
# Trapezoidal silhouette with arched notch at the bottom-center.
# 22 wide × 16 tall = 352 cells.
@export var bunker_w_cells: int = 22
@export var bunker_h_cells: int = 16
@export var bunker_pattern: PackedByteArray = _default_bunker_pattern()


static func _default_bunker_pattern() -> PackedByteArray:
	# Each row literal MUST be exactly 22 characters. Hand-drawn silhouette.
	var rows_ascii: PackedStringArray = PackedStringArray([
		"....11111111111111....",  # 0  trapezoidal top
		"...1111111111111111...",  # 1
		"..111111111111111111..",  # 2
		".11111111111111111111.",  # 3
		"1111111111111111111111",  # 4
		"1111111111111111111111",  # 5
		"1111111111111111111111",  # 6
		"1111111111111111111111",  # 7
		"1111111111111111111111",  # 8
		"1111111111111111111111",  # 9
		"1111111111111111111111",  # 10
		"1111111........1111111",  # 11 notch begins
		"111111..........111111",  # 12
		"11111............11111",  # 13
		"11111............11111",  # 14
		"11111............11111",  # 15
	])
	var out: PackedByteArray = PackedByteArray()
	out.resize(22 * 16)
	for r in range(16):
		var s: String = rows_ascii[r]
		assert(s.length() == 22, "bunker row %d wrong width" % r)
		for c in range(22):
			out[r * 22 + c] = 1 if s[c] == "1" else 0
	return out
