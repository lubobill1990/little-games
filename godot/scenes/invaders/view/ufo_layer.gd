extends Node2D
## UFO renderer + transient score popup. The popup is a scene-only artifact
## derived from snapshot diff (UFO disappeared + score increased on the same
## tick). It fades in/out at the UFO's last position.

const InvadersConfig := preload("res://scripts/invaders/core/invaders_config.gd")
const Palette := preload("res://scripts/invaders/invaders_palette.gd")

const POPUP_DURATION_MS: int = 600

var _cfg: InvadersConfig
var _snap: Dictionary = {}

# Active score popups: Array of {x, y, value, t0_ms}.
var _popups: Array = []


func configure(cfg: InvadersConfig) -> void:
	_cfg = cfg
	set_process(true)
	queue_redraw()


func update_from_snapshot(snap: Dictionary) -> void:
	_snap = snap
	queue_redraw()


func spawn_score_popup(world_x: float, value: int) -> void:
	_popups.append({"x": world_x, "y": _cfg.ufo_y, "value": value, "t0_ms": Time.get_ticks_msec()})
	queue_redraw()


func _process(_delta: float) -> void:
	if _popups.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var i: int = 0
	while i < _popups.size():
		var p: Dictionary = _popups[i]
		if now - int(p["t0_ms"]) > POPUP_DURATION_MS:
			_popups.remove_at(i)
		else:
			i += 1
	queue_redraw()


func _draw() -> void:
	if _cfg == null:
		return
	var ufo: Variant = _snap.get("ufo", null)
	if ufo is Dictionary:
		var x: float = float((ufo as Dictionary).get("x", 0.0))
		var y: float = _cfg.ufo_y
		var hw: float = _cfg.ufo_w * 0.5
		var hh: float = _cfg.ufo_h * 0.5
		draw_rect(Rect2(Vector2(x - hw, y - hh * 0.6), Vector2(hw * 2.0, hh * 1.2)), Palette.UFO, true)
		# Dome cap.
		draw_rect(Rect2(Vector2(x - hw * 0.5, y - hh), Vector2(hw, hh * 0.5)), Palette.UFO, true)
	var now: int = Time.get_ticks_msec()
	for p in _popups:
		var t: float = clampf(float(now - int(p["t0_ms"])) / float(POPUP_DURATION_MS), 0.0, 1.0)
		var alpha: float = 1.0 - t
		var px: float = float(p["x"])
		var py: float = float(p["y"]) - t * 6.0
		var color := Color(Palette.SCORE_POPUP.r, Palette.SCORE_POPUP.g, Palette.SCORE_POPUP.b, alpha)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(px, py), str(int(p["value"])), HORIZONTAL_ALIGNMENT_CENTER, -1.0, 8, color)
