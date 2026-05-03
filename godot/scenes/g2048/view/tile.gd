extends Node2D
## One 2048 tile. Owns its current value, grid cell, and animation state.
## Pooled by g2048.gd — never freed during a session, just hidden when the
## tile dies after a merge.
##
## Animation: callers set `target_cell` and call `start_slide(duration_ms)`.
## _process drives the tween; on completion, position equals the final cell
## center. Pop animation (scale 1.0 → 1.15 → 1.0) is similar but on `scale`.

const Palette := preload("res://scripts/g2048/tile_palette.gd")

var tile_id: int = 0
var value: int = 0
var cell: Vector2i = Vector2i(0, 0)

# Animation state.
var _slide_active: bool = false
var _slide_t: float = 0.0
var _slide_total: float = 0.12   # seconds; 120 ms per Dev plan
var _slide_from: Vector2 = Vector2.ZERO
var _slide_to: Vector2 = Vector2.ZERO

var _pop_active: bool = false
var _pop_t: float = 0.0
var _pop_total: float = 0.10
var _scale_base: float = 1.0
var _scale_peak: float = 1.15

# Spawn fade-in (newly-spawned random tile).
var _fade_active: bool = false
var _fade_t: float = 0.0
var _fade_total: float = 0.08
var _fade_alpha: float = 1.0

# Geometry — set by parent before any animation. Cell pixel size in board space.
var _cell_px: float = 80.0
var _board_origin: Vector2 = Vector2.ZERO
var _gap: float = 6.0   # space between cells (visual gutter)

# A "dier" tile slides to its merge target then disappears. The parent flags
# `is_dier = true` before start_slide; we hide ourselves when the slide ends.
var is_dier: bool = false


func configure(cell_px: float, board_origin: Vector2, gap: float) -> void:
	_cell_px = cell_px
	_board_origin = board_origin
	_gap = gap


func cell_center(c: Vector2i) -> Vector2:
	# Top-left of cell pixel rect, plus half cell minus half gap.
	var stride: float = _cell_px
	var px: float = _board_origin.x + c.x * stride + stride * 0.5
	var py: float = _board_origin.y + c.y * stride + stride * 0.5
	return Vector2(px, py)


func snap_to_cell() -> void:
	position = cell_center(cell)


func start_slide(to_cell: Vector2i, duration_ms: int) -> void:
	_slide_from = position if position != Vector2.ZERO else cell_center(cell)
	_slide_to = cell_center(to_cell)
	_slide_total = max(0.001, float(duration_ms) / 1000.0)
	_slide_t = 0.0
	_slide_active = true


func start_pop() -> void:
	_pop_t = 0.0
	_pop_total = 0.10
	_pop_active = true


func start_fade_in() -> void:
	_fade_alpha = 0.0
	_fade_t = 0.0
	_fade_total = 0.08
	_fade_active = true
	modulate.a = 0.0


func is_animating() -> bool:
	return _slide_active or _pop_active or _fade_active


func _process(delta: float) -> void:
	if _slide_active:
		_slide_t += delta
		var u: float = clamp(_slide_t / _slide_total, 0.0, 1.0)
		# Smoothstep ease — visually nicer than linear, cheap.
		var eased: float = u * u * (3.0 - 2.0 * u)
		position = _slide_from.lerp(_slide_to, eased)
		if u >= 1.0:
			_slide_active = false
			position = _slide_to
			if is_dier:
				visible = false
				is_dier = false

	if _pop_active:
		_pop_t += delta
		var u2: float = clamp(_pop_t / _pop_total, 0.0, 1.0)
		# Triangle wave: 0 → 1 → 0 over the duration.
		var tri: float = 1.0 - absf(u2 * 2.0 - 1.0)
		scale = Vector2.ONE * (_scale_base + (_scale_peak - _scale_base) * tri)
		if u2 >= 1.0:
			_pop_active = false
			scale = Vector2.ONE * _scale_base

	if _fade_active:
		_fade_t += delta
		var u3: float = clamp(_fade_t / _fade_total, 0.0, 1.0)
		_fade_alpha = u3
		modulate.a = u3
		if u3 >= 1.0:
			_fade_active = false
			modulate.a = 1.0

	queue_redraw()


func _draw() -> void:
	if value == 0 or not visible:
		return
	var inset: float = _gap * 0.5
	var w: float = _cell_px - _gap
	var h: float = _cell_px - _gap
	var rect := Rect2(-w * 0.5, -h * 0.5, w, h)
	draw_rect(rect, Palette.bg_for(value), true)
	# Number, centered.
	var font: Font = ThemeDB.fallback_font
	var size: int = Palette.font_size_for(value, w)
	var s: String = str(value)
	var text_size: Vector2 = font.get_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	draw_string(font, Vector2(-text_size.x * 0.5, text_size.y * 0.35),
		s, HORIZONTAL_ALIGNMENT_CENTER, -1, size, Palette.fg_for(value))
