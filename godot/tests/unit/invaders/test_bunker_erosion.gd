extends GutTest
## bunker_erosion.gd — stamp constants and shape.

const BunkerErosion := preload("res://scripts/invaders/core/bunker_erosion.gd")


func test_player_up_stamp_dimensions() -> void:
	var s: PackedByteArray = BunkerErosion.player_up_stamp()
	assert_eq(s.size(), BunkerErosion.PLAYER_UP_W * BunkerErosion.PLAYER_UP_H)
	assert_eq(BunkerErosion.PLAYER_UP_W, 5)
	assert_eq(BunkerErosion.PLAYER_UP_H, 3)


func test_player_up_stamp_pattern() -> void:
	# ".XXX." → 0,1,1,1,0
	# "XXXXX" → 1,1,1,1,1
	# "XXXXX" → 1,1,1,1,1
	var s: PackedByteArray = BunkerErosion.player_up_stamp()
	# Row 0
	assert_eq(s[0], 0); assert_eq(s[1], 1); assert_eq(s[2], 1); assert_eq(s[3], 1); assert_eq(s[4], 0)
	# Row 1
	for i in range(5):
		assert_eq(s[5 + i], 1)
	# Row 2
	for i in range(5):
		assert_eq(s[10 + i], 1)


func test_enemy_down_stamp_dimensions() -> void:
	var s: PackedByteArray = BunkerErosion.enemy_down_stamp()
	assert_eq(s.size(), BunkerErosion.ENEMY_DOWN_W * BunkerErosion.ENEMY_DOWN_H)
	assert_eq(BunkerErosion.ENEMY_DOWN_W, 5)
	assert_eq(BunkerErosion.ENEMY_DOWN_H, 4)


func test_enemy_down_stamp_pattern() -> void:
	# Row 0 "XXXXX", row 1 "XXXXX", row 2 "X...X", row 3 ".X.X."
	var s: PackedByteArray = BunkerErosion.enemy_down_stamp()
	for i in range(5):
		assert_eq(s[i], 1, "row 0 cell %d" % i)
		assert_eq(s[5 + i], 1, "row 1 cell %d" % i)
	# Row 2: X...X → 1,0,0,0,1
	assert_eq(s[10], 1); assert_eq(s[11], 0); assert_eq(s[12], 0); assert_eq(s[13], 0); assert_eq(s[14], 1)
	# Row 3: .X.X. → 0,1,0,1,0
	assert_eq(s[15], 0); assert_eq(s[16], 1); assert_eq(s[17], 0); assert_eq(s[18], 1); assert_eq(s[19], 0)


func test_anchor_constants() -> void:
	# Player-up anchors at bottom-center; enemy-down at top-center.
	assert_eq(BunkerErosion.PLAYER_UP_ANCHOR_SX, 2)
	assert_eq(BunkerErosion.PLAYER_UP_ANCHOR_SY, 2)
	assert_eq(BunkerErosion.ENEMY_DOWN_ANCHOR_SX, 2)
	assert_eq(BunkerErosion.ENEMY_DOWN_ANCHOR_SY, 0)
