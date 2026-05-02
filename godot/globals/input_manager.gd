extends Node
## Cross-platform input layer. Source device (kbd / gamepad / touch) is
## invisible to game scenes — they consume semantic actions via signals or
## `is_action_pressed`. DAS/ARR is implemented once here.
##
## See `docs/input-mapping.md` for the action set.

const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")
const DasArrCls := preload("res://scripts/core/input/das_arr.gd")

signal gamepad_connected(device_id: int, name: String)
signal gamepad_disconnected(device_id: int)
signal action_pressed(action: StringName)
signal action_repeated(action: StringName)
signal action_released(action: StringName)

var das_ms: int = 167:
	set(value):
		das_ms = value
		if _engine:
			_engine.das_ms = value
var arr_ms: int = 33:
	set(value):
		arr_ms = value
		if _engine:
			_engine.arr_ms = value

var _engine: DasArrCls = DasArrCls.new()
var _just_pressed: Dictionary = {}

func _ready() -> void:
	ActionMapDefaults.install()
	_apply_settings_overrides()
	if _has_settings_autoload():
		Settings.changed.connect(_on_settings_changed)
	_engine.das_ms = das_ms
	_engine.arr_ms = arr_ms
	_engine.set_repeatable(ActionMapDefaults.REPEATABLE)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# Held-key safety on scene change.
	for action in ActionMapDefaults.ACTIONS:
		if Input.is_action_pressed(action):
			_emit_engine(_engine.press(action, _now()))

func _has_settings_autoload() -> bool:
	return get_tree().root.has_node("Settings")

# Pull DAS/ARR + per-action rebindings from the Settings autoload (if present)
# and replace InputMap events accordingly. Defaults of the un-overridden slot
# are preserved: if a user only rebinds the keyboard, the gamepad default still
# maps (and vice versa). Reviewer flagged the prior implementation for wiping
# both slots whenever either had a stored override.
func _apply_settings_overrides() -> void:
	if not _has_settings_autoload():
		return
	das_ms = int(Settings.get_value(&"input.das_ms", das_ms))
	arr_ms = int(Settings.get_value(&"input.arr_ms", arr_ms))
	for action in ActionMapDefaults.ACTIONS:
		if action in Settings.RESERVED_ACTIONS:
			continue
		var kbd: InputEvent = Settings.bound_event(action, Settings.SLOT_KBD)
		var pad: InputEvent = Settings.bound_event(action, Settings.SLOT_PAD)
		if kbd == null and pad == null:
			continue
		# Rebuild this action's event list: keep defaults for the slot the user
		# didn't override, drop defaults for the slot they did, then append the
		# user's overrides on top.
		InputMap.action_erase_events(action)
		for ev in ActionMapDefaults.default_events_for(action):
			var is_pad: bool = ActionMapDefaults.is_pad_event(ev)
			if is_pad and pad != null:
				continue
			if not is_pad and kbd != null:
				continue
			InputMap.action_add_event(action, ev)
		if kbd != null:
			InputMap.action_add_event(action, kbd)
		if pad != null:
			InputMap.action_add_event(action, pad)

func _on_settings_changed(key: StringName) -> void:
	var s: String = String(key)
	if s == "input.das_ms":
		das_ms = int(Settings.get_value(&"input.das_ms", das_ms))
	elif s == "input.arr_ms":
		arr_ms = int(Settings.get_value(&"input.arr_ms", arr_ms))
	elif s.begins_with("input.binding."):
		# Re-apply bindings (cheap; only runs on rebind).
		ActionMapDefaults.install()
		_apply_settings_overrides()

func _process(_delta: float) -> void:
	# Detect press / release transitions and feed the engine.
	_just_pressed.clear()
	var now := _now()
	for action in ActionMapDefaults.ACTIONS:
		var pressed := Input.is_action_pressed(action)
		var held := _engine.is_held(action)
		if pressed and not held:
			_just_pressed[action] = true
			_emit_engine(_engine.press(action, now))
		elif held and not pressed:
			_emit_engine(_engine.release(action, now))
	_emit_engine(_engine.tick(now))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_emit_engine(_engine.release_all(_now()))

func is_action_pressed(action: StringName) -> bool:
	return _engine.is_held(action)

func is_action_just_pressed(action: StringName) -> bool:
	return _just_pressed.has(action)

func set_repeat_actions(actions: Array[StringName]) -> void:
	_engine.set_repeatable(actions)

func active_gamepad_name() -> String:
	for id in Input.get_connected_joypads():
		return Input.get_joy_name(id)
	return ""

func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if connected:
		gamepad_connected.emit(device_id, Input.get_joy_name(device_id))
	else:
		gamepad_disconnected.emit(device_id)
		# Conservative: release everything; routing per-device requires
		# tracking which device owns each press, which v1 does not need.
		_emit_engine(_engine.release_all(_now()))

func _emit_engine(events: Array) -> void:
	for ev in events:
		var kind: int = ev[0]
		var action: StringName = ev[1]
		match kind:
			DasArrCls.Event.PRESSED:
				action_pressed.emit(action)
			DasArrCls.Event.REPEATED:
				action_repeated.emit(action)
			DasArrCls.Event.RELEASED:
				action_released.emit(action)

func _now() -> int:
	return Time.get_ticks_msec()
