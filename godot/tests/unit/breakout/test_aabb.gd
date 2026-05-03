extends GutTest
## aabb.gd — overlap, depth, axis selection.

const Aabb := preload("res://scripts/breakout/core/aabb.gd")


func test_overlap_depths_separate_returns_negative() -> void:
	# Two AABBs side by side, no contact. Both depths negative.
	var d := Aabb.overlap_depths(0, 0, 1, 1, 5, 0, 1, 1)
	assert_lt(float(d["x"]), 0.0)
	assert_eq(float(d["y"]), 2.0)  # full vertical overlap


func test_overlap_depths_overlapping() -> void:
	# Two unit AABBs centered (0,0) and (0.5,0.5): both depths = 1.5.
	var d := Aabb.overlap_depths(0, 0, 1, 1, 0.5, 0.5, 1, 1)
	assert_almost_eq(float(d["x"]), 1.5, 1e-6)
	assert_almost_eq(float(d["y"]), 1.5, 1e-6)


func test_overlaps_strict_no_touching() -> void:
	# Edges flush: (0,0,1,1) and (2,0,1,1) touch at x=1; depth=0 → not overlap.
	assert_false(Aabb.overlaps(0, 0, 1, 1, 2, 0, 1, 1))
	# Slight inside → overlap.
	assert_true(Aabb.overlaps(0, 0, 1, 1, 1.9, 0, 1, 1))


func test_dominant_axis_picks_smaller_depth() -> void:
	# X-depth 0.2, Y-depth 1.5 → X wins (we crossed the X face barely).
	var d := {"x": 0.2, "y": 1.5}
	assert_eq(Aabb.dominant_axis(d), "x")
	# Other way.
	var d2 := {"x": 1.5, "y": 0.2}
	assert_eq(Aabb.dominant_axis(d2), "y")


func test_dominant_axis_tie() -> void:
	var d := {"x": 0.5, "y": 0.5}
	assert_eq(Aabb.dominant_axis(d), "tie")
