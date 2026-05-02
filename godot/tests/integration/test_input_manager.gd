extends GutTest
## Scene-level test: drive InputManager via `Input.parse_input_event` with real
## `InputEventKey`s mapped through `InputMap` (per CLAUDE.md §5 test layer rule)
## and assert `action_pressed` / `action_repeated` / `action_released` fire,
## and that focus-loss force-releases held actions.
##
## We use real keys instead of `InputEventAction` because `InputEventAction`
## synthesizes signals but does not flip the state queried by
## `Input.is_action_pressed`, which is what `InputManager._process` polls.

const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")

const _KEY_FOR_ACTION := {
	&"hard_drop": KEY_SPACE,
	&"move_left": KEY_LEFT,
}

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
	for action in _KEY_FOR_ACTION.keys():
		if Input.is_action_pressed(action):
			_send(action, false)
	await get_tree().process_frame

func _im() -> Node:
	return Engine.get_main_loop().root.get_node("InputManager")

func _send(action: StringName, pressed_state: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = _KEY_FOR_ACTION[action]
	ev.physical_keycode = _KEY_FOR_ACTION[action]
	ev.pressed = pressed_state
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func _only(events: Array, action: StringName) -> Array:
	return events.filter(func(a: StringName) -> bool: return a == action)

func test_press_then_release_emits_expected_signals() -> void:
	_send(&"hard_drop", true)
	await get_tree().process_frame
	_send(&"hard_drop", false)
	await get_tree().process_frame
	# KEY_SPACE binds both `hard_drop` and `ui_accept`; filter to the action
	# under test so the assertion stays focused on the InputManager contract.
	assert_eq(_only(pressed, &"hard_drop"), [&"hard_drop"])
	assert_eq(_only(released, &"hard_drop"), [&"hard_drop"])
	assert_eq(_only(repeated, &"hard_drop"), [], "hard_drop is non-repeatable")

func test_hold_repeatable_emits_repeats_after_das() -> void:
	_send(&"move_left", true)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 200:
		await get_tree().process_frame
	_send(&"move_left", false)
	await get_tree().process_frame
	assert_eq(pressed, [&"move_left"])
	assert_gt(repeated.size(), 0, "at least one repeat after DAS")
	assert_eq(released, [&"move_left"])

func test_focus_loss_releases_held_actions() -> void:
	_send(&"move_left", true)
	await get_tree().process_frame
	assert_eq(pressed, [&"move_left"])
	_im().notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await get_tree().process_frame
	assert_eq(released, [&"move_left"], "focus-out releases held actions")
	_send(&"move_left", false)
	await get_tree().process_frame
