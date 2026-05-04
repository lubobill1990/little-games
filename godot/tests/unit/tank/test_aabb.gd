extends GutTest
## tank/core/aabb.gd — overlap predicate, edge-touching == not overlap.

const Aabb := preload("res://scripts/tank/core/aabb.gd")


func test_overlap_when_inside() -> void:
	# A: center (10,10), half (4,4)  → covers [6,14] × [6,14]
	# B: center (12,10), half (4,4)  → covers [8,16] × [6,14]   shared area
	assert_true(Aabb.overlaps(10, 10, 4, 4, 12, 10, 4, 4))


func test_no_overlap_when_disjoint() -> void:
	assert_false(Aabb.overlaps(0, 0, 4, 4, 100, 100, 4, 4))


func test_edge_touching_is_not_overlap() -> void:
	# A right edge at x=4; B left edge at x=4. They share a 0-area boundary,
	# which the contract treats as NOT overlap.
	assert_false(Aabb.overlaps(0, 0, 4, 4, 8, 0, 4, 4))
	# Same on Y axis.
	assert_false(Aabb.overlaps(0, 0, 4, 4, 0, 8, 4, 4))


func test_corner_touching_is_not_overlap() -> void:
	assert_false(Aabb.overlaps(0, 0, 4, 4, 8, 8, 4, 4))


func test_overlap_at_one_subpixel_inside() -> void:
	# Same setup as edge-touching but B shifted in by 1 sub-px → overlap.
	assert_true(Aabb.overlaps(0, 0, 4, 4, 7, 0, 4, 4))


func test_overlap_self() -> void:
	assert_true(Aabb.overlaps(5, 5, 2, 2, 5, 5, 2, 2))


func test_overlap_zero_extent() -> void:
	# Zero-extent AABBs can never overlap by the >0 area definition.
	assert_false(Aabb.overlaps(5, 5, 0, 2, 5, 5, 0, 2))
