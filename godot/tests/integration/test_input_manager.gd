extends GutTest
## Scene-level test: drive InputManager via `Input.action_press` /
## `Input.action_release` (per CLAUDE.md §5 test layer rule) and assert
## `action_pressed` / `action_repeated` / `action_released` fire, and that
## focus-loss force-releases held actions.
##
## We use `Input.action_press` rather than synthesizing `InputEventKey`s
## because the latter is unreliable in headless CI: parsed key events don't
## always propagate to `Input.is_action_pressed` within a small frame budget,
## producing flaky red CI on the same code that passes locally.
## `Input.action_press` directly flips the state `InputManager._process`
## polls, which is the exact contract under test.

const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")

var pressed: Array = []
var repeated: Array = []
var released: Array = []
var _on_pressed: Callable
var _on_repeated: Callable
var _on_released: Callable

func before_each() -> void:
	pressed.clear()
	repeated.clear()
	released.clear()
	var im := _im()
	im.das_ms = 80
	im.arr_ms = 20
	_on_pressed = func(a: StringName) -> void: pressed.append(a)
	_on_repeated = func(a: StringName) -> void: repeated.append(a)
	_on_released = func(a: StringName) -> void: released.append(a)
	im.action_pressed.connect(_on_pressed)
	im.action_repeated.connect(_on_repeated)
	im.action_released.connect(_on_released)

func after_each() -> void:
	var im := _im()
	if im.action_pressed.is_connected(_on_pressed):
		im.action_pressed.disconnect(_on_pressed)
	if im.action_repeated.is_connected(_on_repeated):
		im.action_repeated.disconnect(_on_repeated)
	if im.action_released.is_connected(_on_released):
		im.action_released.disconnect(_on_released)
	for action in ActionMapDefaults.ACTIONS:
		if Input.is_action_pressed(action):
			Input.action_release(action)
	await get_tree().process_frame

func _im() -> Node:
	return Engine.get_main_loop().root.get_node("InputManager")

func test_press_then_release_emits_expected_signals() -> void:
	Input.action_press(&"hard_drop")
	await get_tree().process_frame
	Input.action_release(&"hard_drop")
	await get_tree().process_frame
	assert_eq(pressed, [&"hard_drop"])
	assert_eq(released, [&"hard_drop"])
	assert_eq(repeated, [], "hard_drop is non-repeatable")

func test_hold_repeatable_emits_repeats_after_das() -> void:
	Input.action_press(&"move_left")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 200:
		await get_tree().process_frame
	Input.action_release(&"move_left")
	await get_tree().process_frame
	assert_eq(pressed, [&"move_left"])
	assert_gt(repeated.size(), 0, "at least one repeat after DAS")
	assert_eq(released, [&"move_left"])

func test_focus_loss_releases_held_actions() -> void:
	Input.action_press(&"move_left")
	await get_tree().process_frame
	assert_eq(pressed, [&"move_left"])
	_im().notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await get_tree().process_frame
	assert_eq(released, [&"move_left"], "focus-out releases held actions")
	Input.action_release(&"move_left")
	await get_tree().process_frame
