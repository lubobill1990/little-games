extends RefCounted
## Pure AABB helpers for tank. No Node, no Engine APIs. Local copy —
## intentionally not bridged to invaders/breakout/core to keep cross-game
## coupling at zero (per Dev plan: "aabb.gd local — do not bridge across
## games").
##
## An AABB is `(cx, cy, hx, hy)` — center + half-extents. Units throughout
## tank are integer sub-pixels (1 tile = 16 sub-px), so all four args are
## ints, but we type them as int and use integer math to avoid float drift.

const Self := preload("res://scripts/tank/core/aabb.gd")


## True iff the two AABBs share strictly positive area. Edge-touching
## (depth == 0) is NOT considered overlap. Matches invaders/aabb.gd
## semantics so behavior across games stays predictable.
static func overlaps(acx: int, acy: int, ahx: int, ahy: int,
		bcx: int, bcy: int, bhx: int, bhy: int) -> bool:
	var dx: int = absi(acx - bcx)
	var dy: int = absi(acy - bcy)
	return ((ahx + bhx) - dx) > 0 and ((ahy + bhy) - dy) > 0
