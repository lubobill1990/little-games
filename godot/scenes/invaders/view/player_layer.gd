extends Node2D
## Player ship renderer. Blocky rect with a small triangular top. Modulates
## alpha when the player is invulnerable (recently hit) for a visible flash.

const InvadersConfig := preload("res://scripts/invaders/core/invaders_config.gd")
const Palette := preload("res://scripts/invaders/invaders_palette.gd")

const FLASH_PERIOD_MS: int = 120

var _cfg: InvadersConfig
var _snap: Dictionary = {}


func configure(cfg: InvadersConfig) -> void:
	_cfg = cfg
	queue_redraw()


func update_from_snapshot(snap: Dictionary) -> void:
	_snap = snap
	queue_redraw()


func _draw() -> void:
	if _cfg == null or _snap.is_empty():
		return
	var p: Dictionary = _snap.get("player", {})
	if not bool(p.get("alive", false)):
		return
	var x: float = float(p.get("x", _cfg.world_w * 0.5))
	var y: float = _cfg.player_y
	var hw: float = _cfg.player_w * 0.5
	var hh: float = _cfg.player_h * 0.5
	var color: Color = Palette.PLAYER
	# Invulnerability flash: blink alpha based on remaining ms.
	var iu: int = int(p.get("invuln_until_ms", 0))
	if iu > 0:
		var on: bool = (iu / FLASH_PERIOD_MS) % 2 == 0
		if not on:
			color = Color(color.r, color.g, color.b, 0.35)
	# Body.
	draw_rect(Rect2(Vector2(x - hw, y - hh * 0.5), Vector2(hw * 2.0, hh)), color, true)
	# Triangular cannon top.
	var top := PackedVector2Array([
		Vector2(x - 1.0, y - hh * 0.5),
		Vector2(x + 1.0, y - hh * 0.5),
		Vector2(x + 1.0, y - hh),
		Vector2(x - 1.0, y - hh),
	])
	draw_polygon(top, PackedColorArray([color, color, color, color]))
