extends GutTest
## g2048_merge — pure row math + grid transforms.

const Merge := preload("res://scripts/g2048/core/g2048_merge.gd")


# --- merge_row truth table ---

func test_merge_row_pair_at_left() -> void:
	var r := Merge.merge_row([2, 2, 0, 0])
	assert_eq(r["row"], [4, 0, 0, 0])
	assert_eq(r["gained_score"], 4)


func test_merge_row_two_pairs() -> void:
	# [2,2,4,4] → [4,8,0,0], score += 4 + 8 = 12. Acceptance #2.
	var r := Merge.merge_row([2, 2, 4, 4])
	assert_eq(r["row"], [4, 8, 0, 0])
	assert_eq(r["gained_score"], 12)


func test_merge_row_no_chain() -> void:
	# [4,4,8,0] → [8,8,0,0], NOT [16]. Single merge per cell per step.
	var r := Merge.merge_row([4, 4, 8, 0])
	assert_eq(r["row"], [8, 8, 0, 0])
	assert_eq(r["gained_score"], 8)


func test_merge_row_no_op_when_distinct() -> void:
	# Already-compact row of distinct values: no slide, no merge.
	var r := Merge.merge_row([2, 4, 8, 16])
	assert_eq(r["row"], [2, 4, 8, 16])
	assert_eq(r["gained_score"], 0)
	# All sources are length-1, all match output index → no movement.
	assert_eq(r["sources"], [[0], [1], [2], [3]])


func test_merge_row_compaction_only() -> void:
	# [0,2,0,2] → [4,0,0,0]: zeros removed, then merged.
	var r := Merge.merge_row([0, 2, 0, 2])
	assert_eq(r["row"], [4, 0, 0, 0])
	assert_eq(r["gained_score"], 4)
	# Output index 0 came from source columns 1 and 3.
	assert_eq(r["sources"][0], [1, 3])


func test_merge_row_triple_first_pair() -> void:
	# [2,2,2,0] → [4,2,0,0]: first pair merges, lone 2 slides.
	var r := Merge.merge_row([2, 2, 2, 0])
	assert_eq(r["row"], [4, 2, 0, 0])
	assert_eq(r["gained_score"], 4)


func test_merge_row_full_distinct_no_change() -> void:
	# Acceptance #3 corollary: no-merge no-spawn path.
	var r := Merge.merge_row([2, 4, 2, 4])
	assert_eq(r["row"], [2, 4, 2, 4])
	assert_eq(r["gained_score"], 0)


# --- reverse / transpose ---

func test_reverse_row() -> void:
	assert_eq(Merge.reverse_row([1, 2, 3, 4]), [4, 3, 2, 1])
	assert_eq(Merge.reverse_row([0]), [0])


func test_transpose() -> void:
	var g := [
		[1, 2, 3],
		[4, 5, 6],
		[7, 8, 9],
	]
	var t := Merge.transpose(g)
	assert_eq(t, [
		[1, 4, 7],
		[2, 5, 8],
		[3, 6, 9],
	])


func test_transpose_round_trip() -> void:
	var g := [
		[1, 2, 3, 4],
		[5, 6, 7, 8],
		[9, 10, 11, 12],
		[13, 14, 15, 16],
	]
	assert_eq(Merge.transpose(Merge.transpose(g)), g)
