extends RefCounted
## bunker_erosion.gd — canonical erosion stamps for player-up and
## enemy-down bullet impacts. Stamps are inline ASCII bit-pattern
## constants; tests use them as the oracle (see Dev plan §Algorithms).
##
## A stamp is a flat PackedByteArray of length stamp_w * stamp_h. 1 means
## "clear that cell"; 0 means "leave it". The caller's anchor coordinates
## decide where the stamp lands on the bunker grid.
##
## Anchor convention:
##   - PLAYER_UP_STAMP anchor is the bottom-center of the stamp; aligns
##     with the cell the bullet was last in (the bottom of the bunker).
##   - ENEMY_DOWN_STAMP anchor is the top-center of the stamp; aligns with
##     the cell the bullet entered (the top of the bunker).

const Self := preload("res://scripts/invaders/core/bunker_erosion.gd")


# 5 wide × 3 tall — player bullet eats UPWARD into the bunker bottom.
# Anchor (sx=2, sy=2) is the bottom-center cell of the stamp.
const PLAYER_UP_W: int = 5
const PLAYER_UP_H: int = 3
const PLAYER_UP_ANCHOR_SX: int = 2
const PLAYER_UP_ANCHOR_SY: int = 2

const _PLAYER_UP_ASCII: Array = [
	".XXX.",
	"XXXXX",
	"XXXXX",
]


# 5 wide × 4 tall — enemy bullet eats DOWNWARD into the bunker top.
# Anchor (sx=2, sy=0) is the top-center cell of the stamp. The hollowed
# bottom rows give the classic "bite mark" look without overshooting.
const ENEMY_DOWN_W: int = 5
const ENEMY_DOWN_H: int = 4
const ENEMY_DOWN_ANCHOR_SX: int = 2
const ENEMY_DOWN_ANCHOR_SY: int = 0

const _ENEMY_DOWN_ASCII: Array = [
	"XXXXX",
	"XXXXX",
	"X...X",
	".X.X.",
]


static func player_up_stamp() -> PackedByteArray:
	return _ascii_to_bits(_PLAYER_UP_ASCII, PLAYER_UP_W, PLAYER_UP_H)


static func enemy_down_stamp() -> PackedByteArray:
	return _ascii_to_bits(_ENEMY_DOWN_ASCII, ENEMY_DOWN_W, ENEMY_DOWN_H)


static func _ascii_to_bits(ascii: Array, sw: int, sh: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(sw * sh)
	for sy in range(sh):
		var s: String = ascii[sy]
		assert(s.length() == sw, "stamp row %d wrong width" % sy)
		for sx in range(sw):
			out[sy * sw + sx] = 1 if s[sx] == "X" else 0
	return out
