extends GutTest
## 7-bag fairness, determinism, peek, and reseed.

const PieceKind := preload("res://scripts/tetris/core/piece_kind.gd")
const Bag := preload("res://scripts/tetris/core/bag.gd")

func _pull(b, n: int) -> Array:
	var out: Array = []
	for _i in n:
		out.append(b.next())
	return out

func test_each_consecutive_seven_pulls_form_a_permutation() -> void:
	var b = Bag.create(12345)
	var expected: Array = PieceKind.KINDS.duplicate()
	expected.sort()
	for bag_idx in 5:
		var pulls = _pull(b, 7)
		var got = pulls.duplicate()
		got.sort()
		assert_eq(got, expected, "bag #%d not a permutation: %s" % [bag_idx, str(pulls)])

func test_no_kind_appears_more_than_twice_in_a_row() -> void:
	# Stronger fairness check than just "permutation": across bag boundaries
	# the same piece could appear back-to-back, but never three in a row.
	var b = Bag.create(99)
	var prev2 = -1
	var prev1 = -1
	for _i in 200:
		var k = b.next()
		assert_false(k == prev1 and k == prev2, "three in a row at %d" % _i)
		prev2 = prev1
		prev1 = k

func test_same_seed_same_sequence() -> void:
	var b1 = Bag.create(42)
	var b2 = Bag.create(42)
	for _i in 50:
		assert_eq(b1.next(), b2.next())

func test_different_seed_different_sequence() -> void:
	var b1 = Bag.create(1)
	var b2 = Bag.create(2)
	var s1 = _pull(b1, 14)
	var s2 = _pull(b2, 14)
	assert_ne(s1, s2, "seeds 1 and 2 produced identical 14-pulls")

func test_peek_does_not_consume() -> void:
	var b = Bag.create(7)
	var preview = b.peek(5)
	assert_eq(preview.size(), 5)
	# Pulling 5 should match the preview.
	var pulled = _pull(b, 5)
	assert_eq(pulled, preview)

func test_peek_grows_across_bags() -> void:
	var b = Bag.create(7)
	var preview = b.peek(20)
	assert_eq(preview.size(), 20)
	var pulled = _pull(b, 20)
	assert_eq(pulled, preview)

func test_reseed_after_reset_buffer_changes_stream() -> void:
	var b = Bag.create(1)
	_pull(b, 3)
	b.reset_buffer()
	b.reseed(2)
	var s1 = _pull(b, 14)
	var ref = Bag.create(2)
	var s2 = _pull(ref, 14)
	assert_eq(s1, s2,
			"reseed+reset_buffer should give same stream as a fresh bag with that seed")

func test_only_valid_kinds_returned() -> void:
	var b = Bag.create(9999)
	for _i in 70:
		var k = b.next()
		assert_true(PieceKind.KINDS.has(k), "unexpected kind %d" % k)

func test_seventy_pulls_at_bag_boundary_distribute_evenly() -> void:
	# At the 7-bag boundary specifically (10 full bags = 70 pulls), each kind
	# appears exactly 10 times by construction.
	var b = Bag.create(31415)
	var counts: Dictionary = {}
	for _i in 70:
		var k = b.next()
		counts[k] = counts.get(k, 0) + 1
	for k in PieceKind.KINDS:
		assert_eq(counts.get(k, 0), 10, "kind %d count off" % k)
