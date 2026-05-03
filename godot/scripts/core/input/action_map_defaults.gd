extends Object
## Default action map for `InputManager`. Programmatic registration keeps
## `project.godot`'s `[input]` section clean and reviewable here.

const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"soft_drop", &"hard_drop",
	&"rotate_cw", &"rotate_ccw", &"hold", &"undo", &"pause",
	&"ui_accept", &"ui_cancel",
]

const REPEATABLE: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
]

# Per-action defaults as (slot, value) pairs. Slot is "kbd" → keycode int, or
# "pad" → button_index int. `default_events_for(action)` materializes these
# into fresh InputEvent instances for InputManager._apply_settings_overrides
# so it can selectively replace one slot without erasing the other's defaults.
const _DEFAULTS: Dictionary = {
	&"move_left":  [["kbd", KEY_LEFT], ["kbd", KEY_A],     ["pad", JOY_BUTTON_DPAD_LEFT]],
	&"move_right": [["kbd", KEY_RIGHT], ["kbd", KEY_D],    ["pad", JOY_BUTTON_DPAD_RIGHT]],
	&"move_up":    [["kbd", KEY_UP], ["kbd", KEY_W],       ["pad", JOY_BUTTON_DPAD_UP]],
	&"move_down":  [["kbd", KEY_DOWN], ["kbd", KEY_S],     ["pad", JOY_BUTTON_DPAD_DOWN]],
	&"soft_drop":  [["kbd", KEY_DOWN], ["kbd", KEY_S],     ["pad", JOY_BUTTON_DPAD_DOWN]],
	&"hard_drop":  [["kbd", KEY_SPACE],                    ["pad", JOY_BUTTON_A]],
	&"rotate_cw":  [["kbd", KEY_UP], ["kbd", KEY_X],       ["pad", JOY_BUTTON_B]],
	&"rotate_ccw": [["kbd", KEY_Z],                        ["pad", JOY_BUTTON_X]],
	&"hold":       [["kbd", KEY_C], ["kbd", KEY_SHIFT],    ["pad", JOY_BUTTON_Y], ["pad", JOY_BUTTON_LEFT_SHOULDER]],
	&"undo":       [["kbd", KEY_Z],                        ["pad", JOY_BUTTON_Y]],
	&"pause":      [["kbd", KEY_ESCAPE], ["kbd", KEY_P],   ["pad", JOY_BUTTON_START]],
	&"ui_accept":  [["kbd", KEY_ENTER], ["kbd", KEY_SPACE], ["pad", JOY_BUTTON_A]],
	&"ui_cancel":  [["kbd", KEY_ESCAPE],                   ["pad", JOY_BUTTON_B]],
}

static func install() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		else:
			InputMap.action_erase_events(action)
		for ev in default_events_for(action):
			InputMap.action_add_event(action, ev)

## Return freshly-instantiated default InputEvents for `action`. Callers must
## not mutate them, but they own the instances so each call is safe.
static func default_events_for(action: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not _DEFAULTS.has(action):
		return out
	for entry in _DEFAULTS[action]:
		var slot: String = entry[0]
		var code: int = entry[1]
		if slot == "kbd":
			var k := InputEventKey.new()
			k.keycode = code
			out.append(k)
		elif slot == "pad":
			var b := InputEventJoypadButton.new()
			b.button_index = code
			out.append(b)
	return out

## True iff `event` belongs to the gamepad slot (button or axis motion).
static func is_pad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion

