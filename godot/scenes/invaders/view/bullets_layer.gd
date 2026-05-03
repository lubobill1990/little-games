extends Node2D
## Bullets renderer. Draws the player bullet (white, 2×6) and every enemy
## bullet (2×6, color picked from a small palette by index). Redrawn every
## frame; cost is dominated by enemy bullet count which is capped at ~10.

const InvadersConfig := preload("res://scripts/invaders/core/invaders_config.gd")
const Palette := preload("res://scripts/invaders/invaders_palette.gd")

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
	var pb: Dictionary = _snap.get("player_bullet", {})
	if bool(pb.get("alive", false)):
		var x: float = float(pb.get("x", 0.0))
		var y: float = float(pb.get("y", 0.0))
		var hw: float = _cfg.player_bullet_w * 0.5
		var hh: float = _cfg.player_bullet_h * 0.5
		draw_rect(Rect2(Vector2(x - hw, y - hh), Vector2(_cfg.player_bullet_w, _cfg.player_bullet_h)), Palette.PLAYER_BULLET, true)
	var ebs: Array = _snap.get("enemy_bullets", [])
	for i in range(ebs.size()):
		var b: Dictionary = ebs[i]
		var bx: float = float(b.get("x", 0.0))
		var by: float = float(b.get("y", 0.0))
		var hw2: float = _cfg.enemy_bullet_w * 0.5
		var hh2: float = _cfg.enemy_bullet_h * 0.5
		draw_rect(Rect2(Vector2(bx - hw2, by - hh2), Vector2(_cfg.enemy_bullet_w, _cfg.enemy_bullet_h)), Palette.enemy_bullet_color(i), true)
