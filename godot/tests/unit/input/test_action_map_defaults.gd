extends GutTest
## Verifies that ActionMapDefaults registers all expected actions with at
## least one keyboard and one gamepad event each.

const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")

func before_all() -> void:
	ActionMapDefaults.install()

func test_all_actions_registered() -> void:
	for action in ActionMapDefaults.ACTIONS:
		assert_true(InputMap.has_action(action), "action %s registered" % action)

func test_each_action_has_keyboard_binding() -> void:
	for action in ActionMapDefaults.ACTIONS:
		var has_key := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				has_key = true
				break
		assert_true(has_key, "%s has keyboard binding" % action)

func test_movement_actions_have_gamepad_binding() -> void:
	for action in [&"move_left", &"move_right", &"hard_drop", &"pause"]:
		var has_pad := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton:
				has_pad = true
				break
		assert_true(has_pad, "%s has gamepad binding" % action)

func test_repeatable_subset_is_movement_only() -> void:
	assert_true(ActionMapDefaults.REPEATABLE.has(&"move_left"))
	assert_true(ActionMapDefaults.REPEATABLE.has(&"move_right"))
	assert_true(ActionMapDefaults.REPEATABLE.has(&"move_up"))
	assert_true(ActionMapDefaults.REPEATABLE.has(&"move_down"))
	assert_false(ActionMapDefaults.REPEATABLE.has(&"hard_drop"))
	assert_false(ActionMapDefaults.REPEATABLE.has(&"rotate_cw"))
	assert_false(ActionMapDefaults.REPEATABLE.has(&"pause"))


func test_move_up_down_have_kbd_and_pad_bindings() -> void:
	for action in [&"move_up", &"move_down"]:
		var has_key := false
		var has_pad := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				has_key = true
			elif ev is InputEventJoypadButton:
				has_pad = true
		assert_true(has_key, "%s has keyboard binding" % action)
		assert_true(has_pad, "%s has gamepad binding" % action)
