extends Node2D
## Breakout world renderer. Owns nothing; pulls from the latest snapshot
## given by the parent. Single _draw method paints in three logical
## passes (bricks → paddle → ball) ordered back-to-front; collapses to one
## pass per frame because in this game the cost is dominated by the brick
## count (~50–100) which is well within budget.
##
## The world is drawn in **world units** (config.world_w × config.world_h).
## The parent applies a uniform scale + translation to letterbox it into
## the available viewport.

const Palette := preload("res://scripts/breakout/brick_palette.gd")

var _world_w: float = 320.0
var _world_h: float = 240.0
var _ball_radius: float = 3.0
var _snapshot: Dictionary = {}
# Parallel array; mirrors level.cells so we can resolve color_id by idx for
# bricks present in the latest snapshot (snapshot only carries idx + hp).
var _brick_meta_by_idx: Dictionary = {}

func configure(world_w: float, world_h: float, ball_radius: float, brick_meta_by_idx: Dictionary) -> void:
	_world_w = world_w
	_world_h = world_h
	_ball_radius = ball_radius
	_brick_meta_by_idx = brick_meta_by_idx
	queue_redraw()

func update_from_snapshot(snap: Dictionary) -> void:
	_snapshot = snap
	queue_redraw()

func world_size() -> Vector2:
	return Vector2(_world_w, _world_h)

func _draw() -> void:
	# Background (the playfield itself; letterboxing is parent's job).
	draw_rect(Rect2(Vector2.ZERO, Vector2(_world_w, _world_h)), Palette.BG, true)
	if _snapshot.is_empty():
		return
	# Bricks.
	var bricks: Array = _snapshot.get("bricks", [])
	for entry in bricks:
		var idx: int = int(entry.get("idx", -1))
		if idx < 0:
			continue
		var meta: Dictionary = _brick_meta_by_idx.get(idx, {})
		if meta.is_empty():
			continue
		var cx: float = float(meta.get("cx", 0.0))
		var cy: float = float(meta.get("cy", 0.0))
		var hx: float = float(meta.get("hx", 0.0))
		var hy: float = float(meta.get("hy", 0.0))
		var color_id: int = int(meta.get("color_id", 0))
		var destructible: bool = bool(meta.get("destructible", true))
		var color: Color = Palette.for_color_id(color_id, destructible)
		var rect := Rect2(Vector2(cx - hx, cy - hy), Vector2(hx * 2.0, hy * 2.0))
		draw_rect(rect, color, true)
		# 1px inner border for subtle separation.
		draw_rect(rect, Color(0, 0, 0, 0.35), false, 1.0)
	# Paddle.
	var paddle: Dictionary = _snapshot.get("paddle", {})
	if not paddle.is_empty():
		var px: float = float(paddle.get("x", 0.0))
		var pw: float = float(paddle.get("w", 0.0))
		var ph: float = float(paddle.get("h", 0.0))
		var py: float = float(paddle.get("y", 0.0))
		draw_rect(Rect2(Vector2(px - pw * 0.5, py), Vector2(pw, ph)), Palette.PADDLE, true)
	# Ball — drawn as a filled circle even though core treats it as AABB.
	var ball: Dictionary = _snapshot.get("ball", {})
	if not ball.is_empty():
		var bx: float = float(ball.get("x", 0.0))
		var by: float = float(ball.get("y", 0.0))
		var br: float = float(ball.get("r", _ball_radius))
		draw_circle(Vector2(bx, by), br, Palette.BALL)
