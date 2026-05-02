extends GutTest
## Unit tests for the pure DAS/ARR engine. Exercises every behaviour bullet
## listed in the input-layer Dev plan.

const DasArrCls := preload("res://scripts/core/input/das_arr.gd")

var engine

func before_each() -> void:
	engine = DasArrCls.new()
	engine.das_ms = 200
	engine.arr_ms = 50
	engine.set_repeatable([&"move_left", &"move_right"])

func _kinds(events: Array) -> Array:
	var out: Array = []
	for ev in events:
		out.append(ev[0])
	return out

func test_tap_emits_pressed_only() -> void:
	var p = engine.press(&"move_left", 0)
	assert_eq(_kinds(p), [DasArrCls.Event.PRESSED])
	var t = engine.tick(50)
	assert_eq(t, [], "no repeat before DAS")
	var r = engine.release(&"move_left", 60)
	assert_eq(_kinds(r), [DasArrCls.Event.RELEASED])

func test_hold_past_das_emits_first_repeat() -> void:
	engine.press(&"move_left", 0)
	var t = engine.tick(199)
	assert_eq(t, [], "still under DAS")
	var t2 = engine.tick(200)
	assert_eq(_kinds(t2), [DasArrCls.Event.REPEATED], "first repeat at exactly DAS")

func test_hold_through_das_then_arr_steps() -> void:
	engine.press(&"move_left", 0)
	# Tick at 200 (DAS), 250 (DAS+ARR), 300 (DAS+2*ARR).
	var n: int = 0
	for ms in [200, 250, 300]:
		n += engine.tick(ms).size()
	assert_eq(n, 3, "3 repeats across DAS + 2*ARR steps")

func test_release_mid_das_resets() -> void:
	engine.press(&"move_left", 0)
	engine.release(&"move_left", 100)
	var t = engine.tick(250)
	assert_eq(t, [], "no events after release")

func test_change_das_arr_mid_press_takes_effect_next_press() -> void:
	engine.press(&"move_left", 0)
	engine.das_ms = 1000  # change mid-press
	# Original DAS=200 still applies to the active press.
	assert_eq(_kinds(engine.tick(200)), [DasArrCls.Event.REPEATED])
	engine.release(&"move_left", 300)
	# Next press uses the new DAS.
	engine.press(&"move_left", 400)
	assert_eq(engine.tick(600), [], "new DAS=1000 not yet elapsed")
	assert_eq(_kinds(engine.tick(1400)), [DasArrCls.Event.REPEATED])

func test_non_repeatable_action_never_repeats() -> void:
	engine.press(&"hard_drop", 0)
	for ms in [200, 500, 1000]:
		assert_eq(engine.tick(ms), [], "hard_drop must not repeat")

func test_release_all_emits_one_per_held() -> void:
	engine.press(&"move_left", 0)
	engine.press(&"move_right", 10)
	var out = engine.release_all(20)
	assert_eq(out.size(), 2)
	for ev in out:
		assert_eq(ev[0], DasArrCls.Event.RELEASED)
	assert_false(engine.is_held(&"move_left"))
	assert_false(engine.is_held(&"move_right"))

func test_catchup_clamp_collapses_long_stall() -> void:
	engine.press(&"move_left", 0)
	# 5-second stall past DAS — should not emit ~100 repeats.
	var out = engine.tick(5000)
	assert_eq(out.size(), 1, "catch-up collapses to one repeat")

func test_double_press_is_idempotent() -> void:
	engine.press(&"move_left", 0)
	var second = engine.press(&"move_left", 50)
	assert_eq(second, [], "second press while held is a no-op")
