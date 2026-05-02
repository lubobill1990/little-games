extends GutTest
## Integration test for the InputManager + Settings interaction. The
## Settings autoload stores per-action kbd/pad slot overrides; InputManager
## must apply them in a way that PRESERVES the un-overridden slot's defaults.
##
## Reviewer of PR #25 flagged the original implementation for wiping both
## slots whenever either had a stored override. This test exercises that
## exact scenario: bind only the keyboard slot for `move_left`, then assert
## the gamepad default (`JOY_BUTTON_DPAD_LEFT`) is still mapped.

const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")

func _settings() -> Node:
	return Engine.get_main_loop().root.get_node("Settings")

func _im() -> Node:
	return Engine.get_main_loop().root.get_node("InputManager")

func before_each() -> void:
	# Each test mutates Settings + InputMap; reset to a known-good state.
	_settings().reset_defaults()
	ActionMapDefaults.install()

func after_each() -> void:
	# Same again so we don't contaminate later tests in the run.
	_settings().reset_defaults()
	ActionMapDefaults.install()

func _make_key(keycode: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = keycode
	return k

func _make_pad(button: int) -> InputEventJoypadButton:
	var b := InputEventJoypadButton.new()
	b.button_index = button
	return b

func test_kbd_only_override_preserves_gamepad_default() -> void:
	# Bind only the keyboard slot for move_left to F.
	var s := _settings()
	assert_true(s.bind_event(&"move_left", _make_key(KEY_F), s.SLOT_KBD))

	# Re-apply overrides (mimics _ready or live Settings.changed handler).
	_im()._apply_settings_overrides()

	# The new keyboard binding must be live.
	assert_true(InputMap.action_has_event(&"move_left", _make_key(KEY_F)),
		"new keyboard binding (F) should map to move_left")
	# The gamepad default must STILL be live — this is the regression guard.
	assert_true(InputMap.action_has_event(&"move_left", _make_pad(JOY_BUTTON_DPAD_LEFT)),
		"gamepad default (DPAD_LEFT) should remain mapped after kbd-only rebind")
	# The old keyboard defaults should NOT be live (they were replaced).
	assert_false(InputMap.action_has_event(&"move_left", _make_key(KEY_LEFT)),
		"old keyboard default (LEFT) should be replaced by user binding")
	assert_false(InputMap.action_has_event(&"move_left", _make_key(KEY_A)),
		"old keyboard default (A) should be replaced by user binding")

func test_pad_only_override_preserves_keyboard_defaults() -> void:
	# Mirror of the above: only override the gamepad slot.
	var s := _settings()
	assert_true(s.bind_event(&"move_left", _make_pad(JOY_BUTTON_RIGHT_SHOULDER), s.SLOT_PAD))

	_im()._apply_settings_overrides()

	# New gamepad binding live.
	assert_true(InputMap.action_has_event(&"move_left", _make_pad(JOY_BUTTON_RIGHT_SHOULDER)),
		"new gamepad binding should map to move_left")
	# Keyboard defaults survive.
	assert_true(InputMap.action_has_event(&"move_left", _make_key(KEY_LEFT)),
		"keyboard default (LEFT) should remain mapped after pad-only rebind")
	assert_true(InputMap.action_has_event(&"move_left", _make_key(KEY_A)),
		"keyboard default (A) should remain mapped after pad-only rebind")
	# Old gamepad default replaced.
	assert_false(InputMap.action_has_event(&"move_left", _make_pad(JOY_BUTTON_DPAD_LEFT)),
		"old gamepad default (DPAD_LEFT) should be replaced by user binding")

func test_both_slot_overrides_replace_all_defaults() -> void:
	var s := _settings()
	s.bind_event(&"move_left", _make_key(KEY_F), s.SLOT_KBD)
	s.bind_event(&"move_left", _make_pad(JOY_BUTTON_RIGHT_SHOULDER), s.SLOT_PAD)
	_im()._apply_settings_overrides()
	# Both overrides live, no defaults remain.
	assert_true(InputMap.action_has_event(&"move_left", _make_key(KEY_F)))
	assert_true(InputMap.action_has_event(&"move_left", _make_pad(JOY_BUTTON_RIGHT_SHOULDER)))
	assert_false(InputMap.action_has_event(&"move_left", _make_key(KEY_LEFT)))
	assert_false(InputMap.action_has_event(&"move_left", _make_pad(JOY_BUTTON_DPAD_LEFT)))

func test_no_overrides_preserves_all_defaults() -> void:
	# With nothing in Settings, the action retains its full default set.
	_im()._apply_settings_overrides()
	assert_true(InputMap.action_has_event(&"move_left", _make_key(KEY_LEFT)))
	assert_true(InputMap.action_has_event(&"move_left", _make_key(KEY_A)))
	assert_true(InputMap.action_has_event(&"move_left", _make_pad(JOY_BUTTON_DPAD_LEFT)))
