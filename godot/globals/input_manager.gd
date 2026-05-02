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
	_engine.das_ms = das_ms
	_engine.arr_ms = arr_ms
	_engine.set_repeatable(ActionMapDefaults.REPEATABLE)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# Held-key safety on scene change.
	for action in ActionMapDefaults.ACTIONS:
		if Input.is_action_pressed(action):
			_emit_engine(_engine.press(action, _now()))

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
