class_name DasArr
extends RefCounted
## Pure DAS/ARR repeat engine. No Node, no Input — testable in isolation.
##
## Caller drives it with monotonic ms timestamps from `Time.get_ticks_msec()`.
## Per-action state machine: idle → on press emit PRESSED, schedule DAS → on
## DAS fire emit REPEATED, schedule ARR → on ARR fire (loop) emit REPEATED →
## on release emit RELEASED, reset.

enum Event { PRESSED, REPEATED, RELEASED }

var das_ms: int = 167
var arr_ms: int = 33

var _states: Dictionary = {}
var _repeatable: Dictionary = {}

func set_repeatable(actions: Array) -> void:
	_repeatable.clear()
	for a in actions:
		_repeatable[a] = true

func is_held(action: StringName) -> bool:
	var s: Dictionary = _states.get(action, {})
	return s.get("held", false)

## Records a press. Returns [[Event.PRESSED, action]] (or [] if already held).
func press(action: StringName, now_ms: int) -> Array:
	var s: Dictionary = _states.get(action, {})
	if s.get("held", false):
		return []
	_states[action] = {
		"held": true,
		"next_fire_ms": now_ms + das_ms,
	}
	return [[Event.PRESSED, action]]

## Records a release. Returns [[Event.RELEASED, action]] (or [] if not held).
func release(action: StringName, now_ms: int) -> Array:
	var s: Dictionary = _states.get(action, {})
	if not s.get("held", false):
		return []
	_states.erase(action)
	return [[Event.RELEASED, action]]

## Force-release every held action. Emits one RELEASED per held action.
func release_all(_now_ms: int) -> Array:
	var out: Array = []
	for a in _states.keys():
		out.append([Event.RELEASED, a])
	_states.clear()
	return out

## Advance time and emit any due REPEATED events for repeatable actions.
## Catch-up beyond 250 ms collapses to a single repeat (tab throttle safety).
func tick(now_ms: int) -> Array:
	var out: Array = []
	var step: int = maxi(arr_ms, 1)
	for action in _states.keys():
		if not _repeatable.has(action):
			continue
		var s: Dictionary = _states[action]
		var next_fire: int = s["next_fire_ms"]
		if now_ms < next_fire:
			continue
		if now_ms - next_fire > 250:
			out.append([Event.REPEATED, action])
			s["next_fire_ms"] = now_ms + step
			continue
		while now_ms >= next_fire:
			out.append([Event.REPEATED, action])
			next_fire += step
		s["next_fire_ms"] = next_fire
	return out
