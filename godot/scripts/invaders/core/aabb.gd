extends RefCounted
## Pure AABB helpers for invaders. No Node, no Engine APIs. Local copy —
## intentionally not bridged to breakout/core to keep cross-game coupling
## at zero (per Dev plan: "aabb.gd is local").
##
## An AABB is `(cx, cy, hx, hy)` — center + half-extents.

const Self := preload("res://scripts/invaders/core/aabb.gd")


## True iff the two AABBs share strictly positive area. Edge-touching
## (depth == 0) is NOT considered overlap.
static func overlaps(acx: float, acy: float, ahx: float, ahy: float,
		bcx: float, bcy: float, bhx: float, bhy: float) -> bool:
	var dx: float = absf(acx - bcx)
	var dy: float = absf(acy - bcy)
	return ((ahx + bhx) - dx) > 0.0 and ((ahy + bhy) - dy) > 0.0
