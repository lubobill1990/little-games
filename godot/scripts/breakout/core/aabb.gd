extends RefCounted
## Pure AABB helpers for breakout. No Node, no Engine APIs.
##
## An AABB is `{cx, cy, hx, hy}` — center + half-extents. We picked center
## form (not min/max) because reflection math reads more naturally and the
## brick/paddle/ball state stores positions as centers.
##
## Two-axis penetration depth is the foundation: when two AABBs overlap,
## the depth on each axis tells us:
##   - Whether they overlap at all (both must be > 0).
##   - Which axis to reflect against (the SMALLER depth — i.e. the axis
##     where we just barely entered, which is the face we crossed).
##   - How far to push the ball back to resolve the overlap.

const Self := preload("res://scripts/breakout/core/aabb.gd")


## Returns the per-axis penetration depths between two AABBs. Both will be
## positive iff they overlap. Sign of returned values is always >= 0; the
## caller picks the dominant axis and resolves direction from velocity.
##
## Returned: { "x": float, "y": float } where x = (a.hx + b.hx) - |dx|,
## y similarly. Negative means no overlap on that axis.
static func overlap_depths(acx: float, acy: float, ahx: float, ahy: float,
		bcx: float, bcy: float, bhx: float, bhy: float) -> Dictionary:
	var dx: float = absf(acx - bcx)
	var dy: float = absf(acy - bcy)
	return {
		"x": (ahx + bhx) - dx,
		"y": (ahy + bhy) - dy,
	}


## True iff the two AABBs share any area. Touching-edges (depth == 0) is
## NOT considered overlapping — keeps wall-resting cases stable.
static func overlaps(acx: float, acy: float, ahx: float, ahy: float,
		bcx: float, bcy: float, bhx: float, bhy: float) -> bool:
	var d: Dictionary = overlap_depths(acx, acy, ahx, ahy, bcx, bcy, bhx, bhy)
	return float(d["x"]) > 0.0 and float(d["y"]) > 0.0


## Pick the axis that just barely crossed — the SMALLER overlap. Returns
## "x", "y", or "tie" (depths within `epsilon`). Tie resolution is up to
## the caller; this function does not pick a winner for ties so callers
## can apply deterministic, scenario-specific tiebreaking (e.g. "X wins
## ties for corner sandwich").
static func dominant_axis(depth: Dictionary, epsilon: float = 1e-6) -> String:
	var dx: float = float(depth["x"])
	var dy: float = float(depth["y"])
	if absf(dx - dy) <= epsilon:
		return "tie"
	return "x" if dx < dy else "y"
