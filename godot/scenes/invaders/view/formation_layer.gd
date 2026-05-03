extends Node2D
## Formation renderer. Draws one rect per live enemy plus a per-row "march pose"
## glyph that toggles each formation step (visible "wobble"). Per-cell draw mode
## is just an int 0/1 selecting between two hand-coded shape variants.
##
## Redrawn on:
##  - formation_origin change (formation step)
##  - enemy_mask change (enemy killed)
## Pure renderer: pulls everything from the snapshot the parent passes in.

const InvadersConfig := preload("res://scripts/invaders/core/invaders_config.gd")
const InvadersLevel := preload("res://scripts/invaders/core/invaders_level.gd")
const Palette := preload("res://scripts/invaders/invaders_palette.gd")

var _cfg: InvadersConfig
var _level: InvadersLevel
var _snap: Dictionary = {}
var _pose: int = Palette.MARCH_POSE_A


func configure(cfg: InvadersConfig, lvl: InvadersLevel) -> void:
	_cfg = cfg
	_level = lvl
	queue_redraw()


func update_from_snapshot(snap: Dictionary, pose: int) -> void:
	_snap = snap
	_pose = pose
	queue_redraw()


## Test accessor — current march pose. Exposed for the scene test that asserts
## the pose alternates across two consecutive formation steps.
func march_pose() -> int:
	return _pose


func _draw() -> void:
	if _cfg == null or _snap.is_empty():
		return
	var fm: Dictionary = _snap.get("formation", {})
	var ox: float = float(fm.get("ox", 0.0))
	var oy: float = float(fm.get("oy", 0.0))
	var live: PackedByteArray = _snap.get("enemies", PackedByteArray())
	var rows: int = _cfg.rows
	var cols: int = _cfg.cols
	if live.size() < rows * cols:
		return
	var hx: float = _cfg.enemy_hx
	var hy: float = _cfg.enemy_hy
	for r in range(rows):
		var color: Color = Palette.row_color(r)
		for c in range(cols):
			if live[r * cols + c] != 1:
				continue
			var cx: float = ox + c * _cfg.cell_w + _cfg.cell_w * 0.5
			var cy: float = oy + r * _cfg.cell_h + _cfg.cell_h * 0.5
			_draw_enemy(cx, cy, hx, hy, color, _pose)


func _draw_enemy(cx: float, cy: float, hx: float, hy: float, color: Color, pose: int) -> void:
	# Body: solid rect with a 1-px notch on alternating poses for the "wobble".
	var body := Rect2(Vector2(cx - hx, cy - hy), Vector2(hx * 2.0, hy * 2.0))
	draw_rect(body, color, true)
	# Tiny "legs" rectangle: pose A draws legs at corners, pose B in the middle.
	var leg_w: float = 1.0
	var leg_h: float = 1.5
	var ly: float = cy + hy
	if pose == Palette.MARCH_POSE_A:
		draw_rect(Rect2(Vector2(cx - hx, ly), Vector2(leg_w, leg_h)), color, true)
		draw_rect(Rect2(Vector2(cx + hx - leg_w, ly), Vector2(leg_w, leg_h)), color, true)
	else:
		draw_rect(Rect2(Vector2(cx - leg_w * 0.5, ly), Vector2(leg_w, leg_h)), color, true)
