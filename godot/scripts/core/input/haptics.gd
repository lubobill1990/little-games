extends RefCounted
## Cross-platform haptic pulse.
##
## Calls `Input.vibrate_handheld` on mobile (single-pad parameter accepted) and
## `Input.start_joy_vibration` for the first connected gamepad. Both are no-ops
## on headless / unsupported platforms, which is what we want for CI.
##
## `intensity` is 0..1 weak-rumble strength; `duration_ms` is how long.

static func pulse(intensity: float, duration_ms: int) -> void:
	intensity = clamp(intensity, 0.0, 1.0)
	if intensity <= 0.0 or duration_ms <= 0:
		return
	# Mobile: handheld vibration only takes a duration.
	Input.vibrate_handheld(duration_ms)
	# Gamepad: pulse the first connected one. Pads still report on web exports;
	# on platforms without rumble, the call is a documented no-op.
	for id in Input.get_connected_joypads():
		Input.start_joy_vibration(id, intensity * 0.6, intensity, float(duration_ms) / 1000.0)
		break


## Linear-interpolate intensity by `value`'s position in `tiers`. `tiers` is an
## ordered list of (threshold, intensity, duration_ms) tuples; the first tier
## whose `value < threshold` wins. The final tier is the cap (its threshold is
## ignored — used as a fallback). Pure helper, no side effects.
static func tier_for(value: int, tiers: Array) -> Dictionary:
	for i in tiers.size() - 1:
		var t: Array = tiers[i]
		if value < int(t[0]):
			return {"intensity": float(t[1]), "duration_ms": int(t[2])}
	var last: Array = tiers[tiers.size() - 1]
	return {"intensity": float(last[1]), "duration_ms": int(last[2])}
