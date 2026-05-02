extends GutTest
## Scoring: Guideline base values, B2B (1.5x), combo (50*combo*level), drops.

const Scoring := preload("res://scripts/tetris/core/scoring.gd")
const TSpin := preload("res://scripts/tetris/core/t_spin.gd")

func _new() -> Scoring:
	return Scoring.new()

# --- Base line-clear values at level 1 ---

func test_single_clear_is_100() -> void:
	var s = _new()
	assert_eq(s.register_lock(1, TSpin.NONE), 100)
	assert_eq(s.score, 100)
	assert_eq(s.lines, 1)

func test_double_clear_is_300() -> void:
	var s = _new()
	assert_eq(s.register_lock(2, TSpin.NONE), 300)

func test_triple_clear_is_500() -> void:
	var s = _new()
	assert_eq(s.register_lock(3, TSpin.NONE), 500)

func test_tetris_clear_is_800() -> void:
	var s = _new()
	assert_eq(s.register_lock(4, TSpin.NONE), 800)

func test_zero_clear_no_t_spin_is_zero() -> void:
	var s = _new()
	assert_eq(s.register_lock(0, TSpin.NONE), 0)
	assert_eq(s.score, 0)

# --- T-spin scoring ---

func test_t_spin_no_lines_is_400() -> void:
	var s = _new()
	assert_eq(s.register_lock(0, TSpin.FULL), 400)

func test_t_spin_single_is_800() -> void:
	var s = _new()
	assert_eq(s.register_lock(1, TSpin.FULL), 800)

func test_t_spin_double_is_1200() -> void:
	var s = _new()
	assert_eq(s.register_lock(2, TSpin.FULL), 1200)

func test_t_spin_triple_is_1600() -> void:
	var s = _new()
	assert_eq(s.register_lock(3, TSpin.FULL), 1600)

func test_t_spin_mini_no_lines_is_100() -> void:
	var s = _new()
	assert_eq(s.register_lock(0, TSpin.MINI), 100)

func test_t_spin_mini_single_is_200() -> void:
	var s = _new()
	assert_eq(s.register_lock(1, TSpin.MINI), 200)

# --- B2B chain ---

func test_b2b_chain_of_two_tetrises_applies_1_5x_to_second() -> void:
	var s = _new()
	# First tetris: 800 (no B2B yet, b2b becomes 0).
	assert_eq(s.register_lock(4, TSpin.NONE), 800)
	# Second tetris: 800 * 1.5 = 1200, plus combo bonus (combo=1, level=1) = 50.
	# We're at level 1 throughout because lines = 4 then 8 (still <10).
	var added = s.register_lock(4, TSpin.NONE)
	assert_eq(added, 1200 + 50)

func test_b2b_chain_of_three_tetrises() -> void:
	var s = _new()
	s.register_lock(4, TSpin.NONE)              # 800, b2b=0, combo=0
	s.register_lock(4, TSpin.NONE)              # 1200 + 50 (combo=1)
	# Third clear: lines = 8 → level still 1 because lines/10 = 0; after this clear lines = 12.
	# Lock-time level multiplier applies BEFORE the level update, so still level=1.
	var added = s.register_lock(4, TSpin.NONE)  # 1200 + 100 (combo=2)
	assert_eq(added, 1200 + 100)

func test_non_difficult_clear_breaks_b2b() -> void:
	var s = _new()
	s.register_lock(4, TSpin.NONE)  # b2b → 0
	s.register_lock(1, TSpin.NONE)  # single (non-difficult) → b2b reset
	# Next tetris should be 800 again, not 1200.
	var added = s.register_lock(4, TSpin.NONE)
	# combo bonus: this is the third consecutive clear, combo=2 by now. (single → combo=1, tetris → combo=2)
	# 800 + 50*2*1 = 900.
	assert_eq(added, 800 + 100)

func test_b2b_with_t_spin_single() -> void:
	var s = _new()
	# Tetris first puts us in B2B.
	s.register_lock(4, TSpin.NONE)  # 800, combo=0
	# T-spin single (difficult) extends B2B → (800 base * 1.5) + combo*50 = 1200 + 50 = 1250.
	# Wait: T-spin single base is 800, not the tetris's 800. Let me recompute:
	# base = 800 (T-spin single at level 1) * 1.5 = 1200 by B2B; combo=1 → +50.
	var added = s.register_lock(1, TSpin.FULL)
	assert_eq(added, 1200 + 50)

func test_t_spin_no_lines_does_not_set_b2b() -> void:
	var s = _new()
	# A T-spin with 0 rows is not "difficult" because difficult requires rows>=1.
	s.register_lock(0, TSpin.FULL)        # 400, b2b stays -1, combo stays -1
	# Subsequent tetris should NOT get the 1.5x.
	var added = s.register_lock(4, TSpin.NONE)
	assert_eq(added, 800)  # combo bonus 0 because previous lock had 0 rows (combo reset to -1).

# --- Combo bonus ---

func test_combo_bonus_scales_with_count_and_level() -> void:
	var s = _new()
	# Two consecutive singles. First single: combo=0 → no combo bonus. Score = 100.
	assert_eq(s.register_lock(1, TSpin.NONE), 100)
	# Second single: combo=1 → bonus = 50*1*1 = 50. Score added = 100 + 50 = 150.
	assert_eq(s.register_lock(1, TSpin.NONE), 150)
	# Third single: combo=2 → bonus = 50*2*1 = 100. Score added = 100 + 100 = 200.
	assert_eq(s.register_lock(1, TSpin.NONE), 200)

func test_lock_with_no_clear_resets_combo() -> void:
	var s = _new()
	s.register_lock(1, TSpin.NONE)  # combo=0
	s.register_lock(1, TSpin.NONE)  # combo=1, +50
	s.register_lock(0, TSpin.NONE)  # combo reset to -1
	# Next single: combo back to 0 → no combo bonus.
	var added = s.register_lock(1, TSpin.NONE)
	assert_eq(added, 100)

# --- Drops ---

func test_soft_drop_one_per_cell() -> void:
	var s = _new()
	assert_eq(s.add_soft_drop(7), 7)
	assert_eq(s.score, 7)

func test_hard_drop_two_per_cell() -> void:
	var s = _new()
	assert_eq(s.add_hard_drop(5), 10)
	assert_eq(s.score, 10)

func test_negative_drop_cells_clamped_to_zero() -> void:
	var s = _new()
	assert_eq(s.add_soft_drop(-3), 0)
	assert_eq(s.add_hard_drop(-3), 0)
	assert_eq(s.score, 0)

# --- Level curve ---

func test_level_advances_every_ten_lines() -> void:
	var s = _new()
	for _i in 10:
		s.register_lock(1, TSpin.NONE)
	assert_eq(s.lines, 10)
	assert_eq(s.level, 2)
	for _i in 10:
		s.register_lock(1, TSpin.NONE)
	assert_eq(s.lines, 20)
	assert_eq(s.level, 3)

func test_score_uses_pre_update_level() -> void:
	var s = _new()
	# Get to lines=9 with no level changes.
	for _i in 9:
		s.register_lock(1, TSpin.NONE)
	assert_eq(s.level, 1)
	# 10th single: still level 1 at scoring time → 100 base, + 50*9 combo bonus = 100 + 450 = 550.
	# Then level becomes 2.
	var added = s.register_lock(1, TSpin.NONE)
	assert_eq(added, 100 + 50 * 9 * 1)
	assert_eq(s.level, 2)

# --- Perfect clear ---

func test_perfect_clear_single_is_800() -> void:
	var s = _new()
	assert_eq(s.register_perfect_clear(1, false), 800)

func test_perfect_clear_tetris_b2b_is_3200() -> void:
	var s = _new()
	assert_eq(s.register_perfect_clear(4, true), 3200)

func test_reset_zeroes_state() -> void:
	var s = _new()
	s.register_lock(4, TSpin.NONE)
	s.add_hard_drop(20)
	s.reset()
	assert_eq(s.score, 0)
	assert_eq(s.level, 1)
	assert_eq(s.lines, 0)
	assert_eq(s.combo, -1)
	assert_eq(s.b2b, -1)
