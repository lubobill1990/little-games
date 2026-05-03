extends GutTest
## tank_level.gd — pure parser tests (covers every documented failure mode
## per acceptance #20 in issue #52).

const TankLevel := preload("res://scripts/tank/core/tank_level.gd")


# --- helpers ---

func _good_tiles_2p() -> String:
	# 13 rows × 13 chars; 2 P, 4 E, 1 H. Identical layout to fixtures/level01.txt
	# so the in-test text and the on-disk fixture stay in lockstep.
	return "\n".join([
		".............",
		".....E.E.E...",
		".............",
		".BBB.SSSS....",
		".BBB.SSSS....",
		".BBB.SSSS....",
		".BBB.........",
		"......WWW....",
		"......WWW....",
		".....GGGGG...",
		".....GIIIG...",
		".....P.HP...E",
		".............",
	])


func _good_tiles_1p() -> String:
	# Single-P variant by deleting one of the two P's from the 2P map.
	return "\n".join([
		".............",
		".....E.E.E...",
		".............",
		".BBB.SSSS....",
		".BBB.SSSS....",
		".BBB.SSSS....",
		".BBB.........",
		"......WWW....",
		"......WWW....",
		".....GGGGG...",
		".....GIIIG...",
		".....P.H....E",
		".............",
	])


func _good_roster() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for i in range(20):
		# Bonus on lines 4, 11, 18 (1-indexed → 0-indexed 3, 10, 17).
		var bonus_suffix: String = " +bonus" if (i == 3 or i == 10 or i == 17) else ""
		lines.append("basic%s" % bonus_suffix)
	return "\n".join(lines)


# --- tile parser happy paths ---

func test_parse_tiles_2p_ok() -> void:
	var rows: Variant = TankLevel.parse_tiles(_good_tiles_2p(), 2)
	assert_typeof(rows, TYPE_PACKED_STRING_ARRAY)
	assert_eq(rows.size(), 13)
	for r in range(13):
		assert_eq((rows[r] as String).length(), 13, "row %d width" % r)


func test_parse_tiles_1p_ok() -> void:
	var rows: Variant = TankLevel.parse_tiles(_good_tiles_1p(), 1)
	assert_typeof(rows, TYPE_PACKED_STRING_ARRAY)
	assert_eq(rows.size(), 13)


func test_parse_tiles_crlf_tolerated() -> void:
	var crlf_text: String = _good_tiles_2p().replace("\n", "\r\n")
	var rows: Variant = TankLevel.parse_tiles(crlf_text, 2)
	assert_typeof(rows, TYPE_PACKED_STRING_ARRAY)
	assert_eq(rows.size(), 13)


# --- tile parser failure modes ---

func test_parse_tiles_wrong_player_count() -> void:
	# 1P expects 1 P, but 2P fixture has 2 → mismatch.
	var rows: Variant = TankLevel.parse_tiles(_good_tiles_2p(), 1)
	assert_eq(rows, null)
	assert_push_error("tank_level:")


func test_parse_tiles_wrong_dimensions_too_few() -> void:
	var bad: String = "\n".join([
		".............",
		".....P.H.....",
		".....E.......",
	])
	var rows: Variant = TankLevel.parse_tiles(bad, 1)
	assert_eq(rows, null)
	assert_push_error("tank_level:")


func test_parse_tiles_wrong_row_width() -> void:
	# Take a good 2P map but truncate row 5 by one char.
	var lines: PackedStringArray = _good_tiles_2p().split("\n")
	lines[5] = (lines[5] as String).substr(0, 12)  # 12 instead of 13
	var rows: Variant = TankLevel.parse_tiles("\n".join(lines), 2)
	assert_eq(rows, null)
	assert_push_error("tank_level:")


func test_parse_tiles_unknown_char() -> void:
	# Replace a known tile with an alien char.
	var lines: PackedStringArray = _good_tiles_2p().split("\n")
	# Swap the very first '.' for 'Z'.
	var l0: String = lines[0]
	lines[0] = "Z" + l0.substr(1)
	var rows: Variant = TankLevel.parse_tiles("\n".join(lines), 2)
	assert_eq(rows, null)
	assert_push_error("tank_level:")


func test_parse_tiles_missing_base() -> void:
	# Strip the H out.
	var lines: PackedStringArray = _good_tiles_2p().split("\n")
	for i in range(lines.size()):
		lines[i] = (lines[i] as String).replace("H", ".")
	var rows: Variant = TankLevel.parse_tiles("\n".join(lines), 2)
	assert_eq(rows, null)
	assert_push_error("tank_level:")


func test_parse_tiles_missing_enemy_spawn() -> void:
	# Strip every E.
	var lines: PackedStringArray = _good_tiles_2p().split("\n")
	for i in range(lines.size()):
		lines[i] = (lines[i] as String).replace("E", ".")
	var rows: Variant = TankLevel.parse_tiles("\n".join(lines), 2)
	assert_eq(rows, null)
	assert_push_error("tank_level:")


func test_parse_tiles_invalid_player_count_arg() -> void:
	# player_count must be 1 or 2.
	var rows: Variant = TankLevel.parse_tiles(_good_tiles_2p(), 0)
	assert_eq(rows, null)
	assert_push_error("tank_level:")
	var rows2: Variant = TankLevel.parse_tiles(_good_tiles_2p(), 3)
	assert_eq(rows2, null)
	assert_push_error("tank_level:")


# --- roster parser happy paths ---

func test_parse_roster_ok() -> void:
	var roster: Variant = TankLevel.parse_roster(_good_roster())
	assert_typeof(roster, TYPE_ARRAY)
	assert_eq(roster.size(), 20)
	# Bonus markers on indices 3, 10, 17.
	var bonus_ix: Array = []
	for i in range(roster.size()):
		if (roster[i] as Dictionary)["bonus"]:
			bonus_ix.append(i)
	assert_eq(bonus_ix, [3, 10, 17])


func test_parse_roster_comments_and_blank_lines_ignored() -> void:
	var with_noise: String = "# header comment\n\n" + _good_roster() + "\n# trailing\n"
	var roster: Variant = TankLevel.parse_roster(with_noise)
	assert_typeof(roster, TYPE_ARRAY)
	assert_eq(roster.size(), 20)


func test_parse_roster_crlf_tolerated() -> void:
	var roster: Variant = TankLevel.parse_roster(_good_roster().replace("\n", "\r\n"))
	assert_typeof(roster, TYPE_ARRAY)
	assert_eq(roster.size(), 20)


func test_parse_roster_mixed_kinds() -> void:
	var lines: PackedStringArray = PackedStringArray([
		"basic", "fast", "power", "armor",
		"basic +bonus",
		"basic", "basic", "basic", "basic", "basic",
		"fast +bonus",
		"basic", "basic", "basic", "basic", "basic", "basic",
		"power +bonus",
		"basic", "armor",
	])
	var roster: Variant = TankLevel.parse_roster("\n".join(lines))
	assert_typeof(roster, TYPE_ARRAY)
	assert_eq(roster.size(), 20)
	assert_eq((roster[0] as Dictionary)["kind"], "basic")
	assert_eq((roster[2] as Dictionary)["kind"], "power")
	assert_eq((roster[3] as Dictionary)["kind"], "armor")
	assert_true((roster[4] as Dictionary)["bonus"])


# --- roster parser failure modes ---

func test_parse_roster_unknown_kind() -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("ufo")
	for i in range(19):
		lines.append("basic" if i != 2 else "basic +bonus")
	var roster: Variant = TankLevel.parse_roster("\n".join(lines))
	assert_eq(roster, null)
	assert_push_error("tank_level:")


func test_parse_roster_unknown_tag() -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("basic +rocketlauncher")
	for i in range(19):
		lines.append("basic")
	var roster: Variant = TankLevel.parse_roster("\n".join(lines))
	assert_eq(roster, null)
	assert_push_error("tank_level:")


func test_parse_roster_too_few_entries() -> void:
	var lines: PackedStringArray = PackedStringArray(["basic", "basic", "basic"])
	var roster: Variant = TankLevel.parse_roster("\n".join(lines))
	assert_eq(roster, null)
	assert_push_error("tank_level:")


func test_parse_roster_too_many_entries() -> void:
	var lines: PackedStringArray = PackedStringArray()
	for i in range(25):
		lines.append("basic +bonus" if i < 3 else "basic")
	var roster: Variant = TankLevel.parse_roster("\n".join(lines))
	assert_eq(roster, null)
	assert_push_error("tank_level:")


func test_parse_roster_wrong_bonus_count_zero() -> void:
	var lines: PackedStringArray = PackedStringArray()
	for i in range(20):
		lines.append("basic")  # no +bonus markers anywhere
	var roster: Variant = TankLevel.parse_roster("\n".join(lines))
	assert_eq(roster, null)
	assert_push_error("tank_level:")


func test_parse_roster_wrong_bonus_count_too_many() -> void:
	var lines: PackedStringArray = PackedStringArray()
	for i in range(20):
		# 5 bonus markers — too many.
		lines.append("basic +bonus" if i < 5 else "basic")
	var roster: Variant = TankLevel.parse_roster("\n".join(lines))
	assert_eq(roster, null)
	assert_push_error("tank_level:")


# --- combined parse_level + helpers ---

func test_parse_level_2p_returns_p1_and_p2() -> void:
	var out: Variant = TankLevel.parse_level(_good_tiles_2p(), _good_roster(), 2)
	assert_typeof(out, TYPE_DICTIONARY)
	var d: Dictionary = out as Dictionary
	assert_typeof(d["tiles"], TYPE_PACKED_STRING_ARRAY)
	assert_eq((d["tiles"] as PackedStringArray).size(), 13)
	assert_eq((d["roster"] as Array).size(), 20)
	# P1 is topmost-leftmost; P2 is the next one.
	# Both Ps in the 2P fixture sit on row 11 at cols 5 and 8.
	assert_eq(d["p1"], [5, 11])
	assert_eq(d["p2"], [8, 11])


func test_parse_level_1p_p2_is_null() -> void:
	var out: Variant = TankLevel.parse_level(_good_tiles_1p(), _good_roster(), 1)
	assert_typeof(out, TYPE_DICTIONARY)
	var d: Dictionary = out as Dictionary
	assert_eq(d["p1"], [5, 11])
	assert_eq(d["p2"], null)


func test_parse_level_propagates_tile_failure() -> void:
	# Bad tile map → whole parse fails.
	var bad_tiles: String = _good_tiles_2p().substr(0, 50)  # truncated
	var out: Variant = TankLevel.parse_level(bad_tiles, _good_roster(), 2)
	assert_eq(out, null)
	assert_push_error("tank_level:")


func test_parse_level_propagates_roster_failure() -> void:
	var bad_roster: String = "basic\nbasic\nbasic\n"  # only 3 lines
	var out: Variant = TankLevel.parse_level(_good_tiles_2p(), bad_roster, 2)
	assert_eq(out, null)
	assert_push_error("tank_level:")


func test_find_enemy_spawns_declaration_order() -> void:
	var rows: Variant = TankLevel.parse_tiles(_good_tiles_2p(), 2)
	assert_typeof(rows, TYPE_PACKED_STRING_ARRAY)
	var spawns: Array = TankLevel.find_enemy_spawns(rows)
	# 2P fixture has 4 E spawns: row 1 cols 5,7,9 and row 11 col 12.
	# Top-to-bottom, left-to-right ordering.
	assert_eq(spawns.size(), 4)
	assert_eq(spawns[0], [5, 1])
	assert_eq(spawns[1], [7, 1])
	assert_eq(spawns[2], [9, 1])
	assert_eq(spawns[3], [12, 11])


func test_find_base_returns_topmost_leftmost() -> void:
	var rows: Variant = TankLevel.parse_tiles(_good_tiles_2p(), 2)
	assert_typeof(rows, TYPE_PACKED_STRING_ARRAY)
	var base: Array = TankLevel.find_base(rows)
	# H sits in row 11 col 7 in the 2P fixture.
	assert_eq(base, [7, 11])


# --- on-disk fixture round-trip — guards "fixture vs in-test text drift". ---

func test_disk_fixture_parses() -> void:
	var f: FileAccess = FileAccess.open("res://tests/unit/tank/fixtures/level01.txt", FileAccess.READ)
	assert_not_null(f, "fixture level01.txt missing")
	if f == null:
		return
	var tiles_text: String = f.get_as_text()
	f.close()
	var f2: FileAccess = FileAccess.open("res://tests/unit/tank/fixtures/level01.roster.txt", FileAccess.READ)
	assert_not_null(f2, "fixture level01.roster.txt missing")
	if f2 == null:
		return
	var roster_text: String = f2.get_as_text()
	f2.close()
	var out: Variant = TankLevel.parse_level(tiles_text, roster_text, 2)
	assert_typeof(out, TYPE_DICTIONARY)
