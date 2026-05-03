extends Node
## Settings autoload: in-memory Variant store with debounced ConfigFile-backed
## persistence at `user://settings.cfg`. Pure data + IO; UI lives in
## `scenes/ui/settings/`.
##
## Design:
##   - get_value/set_value (NOT get/set — those shadow Object's reflection methods).
##   - InputEvent serialization uses a versioned structured dict, NOT
##     `var_to_bytes`, since the latter format isn't stable across Godot minor
##     versions (sub-agent review of #5).
##   - Writes are debounced 250 ms after the last set_value to avoid disk thrash
##     during slider drags.
##
## Conventional keys:
##   audio.master / audio.sfx / audio.music     float 0..1
##   input.das_ms / input.arr_ms                int
##   input.binding.<action>.<slot>              dict (kbd | pad slot)
##   tetris.high_score                          int
##
## Each action has up to TWO binding slots so a key and a gamepad button can
## coexist. Slots are the strings "kbd" and "pad".

signal changed(key: StringName)

const CONFIG_PATH: String = "user://settings.cfg"
const SCHEMA_VERSION: int = 1
const DEBOUNCE_MS: int = 250

const SLOT_KBD: String = "kbd"
const SLOT_PAD: String = "pad"
const SLOTS: Array[String] = [SLOT_KBD, SLOT_PAD]

# Actions that must NOT be rebindable (sub-agent review of #5).
const RESERVED_ACTIONS: Array[StringName] = [&"ui_accept", &"ui_cancel"]

const DEFAULTS: Dictionary = {
	&"audio.master": 1.0,
	&"audio.sfx": 1.0,
	&"audio.music": 0.5,
	&"input.das_ms": 167,
	&"input.arr_ms": 33,
	&"tetris.high_score": 0,
}

var _values: Dictionary = {}
var _dirty: bool = false
var _save_timer_ms: int = -1
# Override for tests so they can use a temp path.
var _config_path: String = CONFIG_PATH

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_from_disk()

func _process(_delta: float) -> void:
	if _save_timer_ms < 0:
		return
	_save_timer_ms -= int(_delta * 1000.0)
	if _save_timer_ms <= 0:
		_save_timer_ms = -1
		if _dirty:
			_write_config_file()
			_dirty = false

# --- Public API ---

func get_value(key: StringName, default_value: Variant = null) -> Variant:
	if _values.has(key):
		return _values[key]
	if DEFAULTS.has(key):
		return DEFAULTS[key]
	return default_value

func set_value(key: StringName, value: Variant) -> void:
	if _values.get(key) == value:
		return
	_values[key] = value
	_dirty = true
	_save_timer_ms = DEBOUNCE_MS
	emit_signal("changed", key)

func reset_defaults() -> void:
	_values.clear()
	# Re-emit changed for every default key so listeners refresh.
	for key in DEFAULTS.keys():
		emit_signal("changed", key)
	# Also clear all binding entries.
	for action in InputMap.get_actions():
		emit_signal("changed", _binding_key(action, SLOT_KBD))
		emit_signal("changed", _binding_key(action, SLOT_PAD))
	_dirty = true
	_save_timer_ms = DEBOUNCE_MS

# Bind a single InputEvent to (action, slot). Replaces any prior event in that
# slot but preserves the other slot's binding. Stores a serializable dict.
func bind_event(action: StringName, event: InputEvent, slot: String = SLOT_KBD) -> bool:
	if action in RESERVED_ACTIONS:
		return false
	if slot not in SLOTS:
		return false
	var enc: Dictionary = _encode_event(event)
	if enc.is_empty():
		return false
	set_value(_binding_key(action, slot), enc)
	return true

func bound_event(action: StringName, slot: String = SLOT_KBD) -> InputEvent:
	var enc = get_value(_binding_key(action, slot), null)
	if enc == null:
		return null
	return _decode_event(enc)

# --- Internals ---

func _binding_key(action: StringName, slot: String) -> StringName:
	return StringName("input.binding.%s.%s" % [String(action), slot])

func _write_config_file() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema_version", SCHEMA_VERSION)
	for k in _values.keys():
		# Section/key split: anything before the first dot is the section.
		var s: String = String(k)
		var dot: int = s.find(".")
		if dot < 0:
			cfg.set_value("misc", s, _values[k])
		else:
			cfg.set_value(s.substr(0, dot), s.substr(dot + 1), _values[k])
	cfg.save(_config_path)

func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(_config_path)
	_values.clear()
	if err != OK:
		return
	var stored_version: int = int(cfg.get_value("meta", "schema_version", 0))
	if stored_version != SCHEMA_VERSION:
		# v1: wipe and start fresh on schema mismatch.
		return
	for section in cfg.get_sections():
		if section == "meta":
			continue
		for sub_key in cfg.get_section_keys(section):
			var full: StringName = StringName("%s.%s" % [section, sub_key])
			_values[full] = cfg.get_value(section, sub_key)

# Force an immediate flush (tests; also called on quit if we wire it up later).
func flush() -> void:
	if _dirty:
		_write_config_file()
		_dirty = false
		_save_timer_ms = -1

# --- InputEvent <-> Dict ---

func _encode_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var k: InputEventKey = event
		return {
			"v": SCHEMA_VERSION,
			"type": "key",
			"keycode": k.keycode,
			"physical_keycode": k.physical_keycode,
			"shift": k.shift_pressed,
			"ctrl": k.ctrl_pressed,
			"alt": k.alt_pressed,
			"meta": k.meta_pressed,
		}
	if event is InputEventJoypadButton:
		var b: InputEventJoypadButton = event
		return {
			"v": SCHEMA_VERSION,
			"type": "button",
			"index": b.button_index,
		}
	if event is InputEventJoypadMotion:
		var a: InputEventJoypadMotion = event
		# Capture sign only — store fixed magnitude 1.0 so reconstruction
		# triggers the >=0.5 hysteresis on input but doesn't pin a value.
		return {
			"v": SCHEMA_VERSION,
			"type": "axis",
			"axis": a.axis,
			"sign": (1 if a.axis_value >= 0 else -1),
		}
	return {}

func _decode_event(enc: Dictionary) -> InputEvent:
	if enc.get("v", 0) != SCHEMA_VERSION:
		return null
	match enc.get("type", ""):
		"key":
			var k := InputEventKey.new()
			k.keycode = enc.get("keycode", 0)
			k.physical_keycode = enc.get("physical_keycode", 0)
			k.shift_pressed = enc.get("shift", false)
			k.ctrl_pressed = enc.get("ctrl", false)
			k.alt_pressed = enc.get("alt", false)
			k.meta_pressed = enc.get("meta", false)
			return k
		"button":
			var b := InputEventJoypadButton.new()
			b.button_index = enc.get("index", 0)
			return b
		"axis":
			var a := InputEventJoypadMotion.new()
			a.axis = enc.get("axis", 0)
			a.axis_value = float(enc.get("sign", 1))
			return a
	return null
