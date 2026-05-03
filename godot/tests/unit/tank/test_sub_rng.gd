extends GutTest
## sub_rng.gd — XOR-tag fan-out.

const SubRng := preload("res://scripts/tank/core/sub_rng.gd")


func test_make_seeds_predictably() -> void:
	# Same (master, tag) → byte-identical sequence.
	var a: RandomNumberGenerator = SubRng.make(42, SubRng.TAG_SPAWN)
	var b: RandomNumberGenerator = SubRng.make(42, SubRng.TAG_SPAWN)
	for i in range(10):
		assert_eq(a.randi(), b.randi(), "iter %d" % i)


func test_distinct_tags_give_distinct_streams() -> void:
	var spawn: RandomNumberGenerator = SubRng.make(42, SubRng.TAG_SPAWN)
	var ai_t: RandomNumberGenerator = SubRng.make(42, SubRng.TAG_AI_TARGET)
	# At least one of the first 10 draws should differ — astronomically
	# unlikely otherwise. (Identical = tag table has a collision.)
	var any_diff: bool = false
	for i in range(10):
		if spawn.randi() != ai_t.randi():
			any_diff = true
			break
	assert_true(any_diff, "distinct tags must yield distinct streams")


func test_tag_table_has_no_duplicates() -> void:
	# Guards against accidentally renumbering / colliding tag constants.
	var tags: Array = [
		SubRng.TAG_SPAWN,
		SubRng.TAG_AI_TARGET,
		SubRng.TAG_AI_FIRE,
		SubRng.TAG_DROP,
		SubRng.TAG_PICK,
	]
	var seen: Dictionary = {}
	for t in tags:
		assert_false(seen.has(t), "duplicate tag value 0x%x" % t)
		seen[t] = true
