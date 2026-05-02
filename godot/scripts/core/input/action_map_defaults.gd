extends Object
## Default action map for `InputManager`. Programmatic registration keeps
## `project.godot`'s `[input]` section clean and reviewable here.

const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"soft_drop", &"hard_drop",
	&"rotate_cw", &"rotate_ccw", &"hold", &"pause",
	&"ui_accept", &"ui_cancel",
]

const REPEATABLE: Array[StringName] = [
	&"move_left", &"move_right",
]

static func install() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		else:
			InputMap.action_erase_events(action)
	_bind_keyboard()
	_bind_gamepad()

static func _bind_keyboard() -> void:
	_add_key(&"move_left", KEY_LEFT)
	_add_key(&"move_left", KEY_A)
	_add_key(&"move_right", KEY_RIGHT)
	_add_key(&"move_right", KEY_D)
	_add_key(&"soft_drop", KEY_DOWN)
	_add_key(&"soft_drop", KEY_S)
	_add_key(&"hard_drop", KEY_SPACE)
	_add_key(&"rotate_cw", KEY_UP)
	_add_key(&"rotate_cw", KEY_X)
	_add_key(&"rotate_ccw", KEY_Z)
	_add_key(&"hold", KEY_C)
	_add_key(&"hold", KEY_SHIFT)
	_add_key(&"pause", KEY_ESCAPE)
	_add_key(&"pause", KEY_P)
	_add_key(&"ui_accept", KEY_ENTER)
	_add_key(&"ui_accept", KEY_SPACE)
	_add_key(&"ui_cancel", KEY_ESCAPE)

static func _bind_gamepad() -> void:
	_add_pad(&"move_left", JOY_BUTTON_DPAD_LEFT)
	_add_pad(&"move_right", JOY_BUTTON_DPAD_RIGHT)
	_add_pad(&"soft_drop", JOY_BUTTON_DPAD_DOWN)
	_add_pad(&"hard_drop", JOY_BUTTON_A)
	_add_pad(&"rotate_cw", JOY_BUTTON_B)
	_add_pad(&"rotate_ccw", JOY_BUTTON_X)
	_add_pad(&"hold", JOY_BUTTON_Y)
	_add_pad(&"hold", JOY_BUTTON_LEFT_SHOULDER)
	_add_pad(&"pause", JOY_BUTTON_START)
	_add_pad(&"ui_accept", JOY_BUTTON_A)
	_add_pad(&"ui_cancel", JOY_BUTTON_B)

static func _add_key(action: StringName, keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	InputMap.action_add_event(action, ev)

static func _add_pad(action: StringName, button: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
