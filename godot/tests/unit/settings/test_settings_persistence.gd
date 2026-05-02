extends GutTest
## Settings autoload: persistence + InputEvent serialization round-trip.
##
## We DON'T mutate the live `user://settings.cfg` — each test points the
## autoload at a temp file via `_config_path`, exercises the API, and reloads
## into a SECOND fresh autoload-like instance to assert disk round-trip.

const SettingsScript := preload("res://globals/settings.gd")

var _temp_path: String

func before_each() -> void:
	_temp_path = "user://_test_settings_%d.cfg" % Time.get_ticks_usec()

func after_each() -> void:
	# Best-effort: remove file. Errors ignored; user:// is a sandbox.
	if FileAccess.file_exists(_temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_temp_path))

func _new_settings() -> Node:
	var s = SettingsScript.new()
	s._config_path = _temp_path
	add_child_autofree(s)
	return s

func test_get_returns_default_for_unset_key() -> void:
	var s = _new_settings()
	assert_eq(s.get_value(&"audio.master"), 1.0)
	assert_eq(s.get_value(&"input.das_ms"), 167)
	assert_eq(s.get_value(&"tetris.high_score"), 0)

func test_set_value_emits_changed_signal() -> void:
	var s = _new_settings()
	watch_signals(s)
	s.set_value(&"audio.sfx", 0.4)
	assert_signal_emitted_with_parameters(s, "changed", [&"audio.sfx"])

func test_set_value_then_get_returns_new_value() -> void:
	var s = _new_settings()
	s.set_value(&"audio.master", 0.25)
	assert_eq(s.get_value(&"audio.master"), 0.25)

func test_idempotent_set_does_not_emit_changed_twice() -> void:
	var s = _new_settings()
	s.set_value(&"input.das_ms", 100)
	watch_signals(s)
	s.set_value(&"input.das_ms", 100)  # same value
	assert_signal_emit_count(s, "changed", 0)

func test_persistence_round_trip_after_flush() -> void:
	var s = _new_settings()
	s.set_value(&"audio.master", 0.7)
	s.set_value(&"input.das_ms", 200)
	s.set_value(&"tetris.high_score", 12345)
	s.flush()
	var s2 = _new_settings()
	assert_eq(s2.get_value(&"audio.master"), 0.7)
	assert_eq(s2.get_value(&"input.das_ms"), 200)
	assert_eq(s2.get_value(&"tetris.high_score"), 12345)

func test_debounced_writes_coalesce() -> void:
	# Rapid set_value calls should not flush to disk before the debounce window.
	# We assert by reading the file (or its absence) before/after manual flush.
	var s = _new_settings()
	s.set_value(&"audio.sfx", 0.3)
	s.set_value(&"audio.sfx", 0.4)
	s.set_value(&"audio.sfx", 0.5)
	assert_false(FileAccess.file_exists(_temp_path), "no disk write yet (debounce)")
	s.flush()
	var s2 = _new_settings()
	assert_eq(s2.get_value(&"audio.sfx"), 0.5, "final value persisted")

func test_reset_defaults_clears_overrides() -> void:
	var s = _new_settings()
	s.set_value(&"audio.master", 0.1)
	s.reset_defaults()
	assert_eq(s.get_value(&"audio.master"), 1.0, "back to default after reset")

func test_keyboard_event_round_trip() -> void:
	var s = _new_settings()
	var ev := InputEventKey.new()
	ev.keycode = KEY_F
	ev.shift_pressed = true
	assert_true(s.bind_event(&"move_left", ev, s.SLOT_KBD))
	s.flush()
	var s2 = _new_settings()
	var got: InputEvent = s2.bound_event(&"move_left", s.SLOT_KBD)
	assert_not_null(got)
	assert_true(got is InputEventKey)
	assert_eq((got as InputEventKey).keycode, KEY_F)
	assert_true((got as InputEventKey).shift_pressed)

func test_gamepad_button_round_trip() -> void:
	var s = _new_settings()
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_X
	assert_true(s.bind_event(&"hold", ev, s.SLOT_PAD))
	s.flush()
	var s2 = _new_settings()
	var got: InputEvent = s2.bound_event(&"hold", s.SLOT_PAD)
	assert_not_null(got)
	assert_true(got is InputEventJoypadButton)
	assert_eq((got as InputEventJoypadButton).button_index, JOY_BUTTON_X)

func test_axis_round_trip_preserves_sign() -> void:
	var s = _new_settings()
	var ev := InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_LEFT_Y
	ev.axis_value = -0.7
	assert_true(s.bind_event(&"soft_drop", ev, s.SLOT_PAD))
	s.flush()
	var s2 = _new_settings()
	var got: InputEvent = s2.bound_event(&"soft_drop", s.SLOT_PAD)
	assert_not_null(got)
	assert_true(got is InputEventJoypadMotion)
	assert_eq((got as InputEventJoypadMotion).axis, JOY_AXIS_LEFT_Y)
	assert_lt((got as InputEventJoypadMotion).axis_value, 0.0, "sign preserved")

func test_kbd_and_pad_slots_independent() -> void:
	var s = _new_settings()
	var k := InputEventKey.new(); k.keycode = KEY_J
	var b := InputEventJoypadButton.new(); b.button_index = JOY_BUTTON_Y
	s.bind_event(&"hold", k, s.SLOT_KBD)
	s.bind_event(&"hold", b, s.SLOT_PAD)
	assert_true(s.bound_event(&"hold", s.SLOT_KBD) is InputEventKey)
	assert_true(s.bound_event(&"hold", s.SLOT_PAD) is InputEventJoypadButton)

func test_reserved_actions_cannot_be_rebound() -> void:
	var s = _new_settings()
	var ev := InputEventKey.new(); ev.keycode = KEY_F
	assert_false(s.bind_event(&"ui_accept", ev), "ui_accept is reserved")
	assert_false(s.bind_event(&"ui_cancel", ev), "ui_cancel is reserved")

func test_schema_version_mismatch_wipes_to_defaults() -> void:
	var s = _new_settings()
	s.set_value(&"audio.master", 0.2)
	s.flush()
	# Manually rewrite the file with a mismatched schema_version.
	var cfg := ConfigFile.new()
	cfg.load(_temp_path)
	cfg.set_value("meta", "schema_version", 99999)
	cfg.save(_temp_path)
	var s2 = _new_settings()
	assert_eq(s2.get_value(&"audio.master"), 1.0, "schema mismatch → defaults")
