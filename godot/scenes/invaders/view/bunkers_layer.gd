extends Node2D
## Bunkers renderer. Each bunker is a grid of 1/0 cells; we draw one filled
## rect per live cell, in BUNKER color. Redrawn only when the parent detects
## a bunker diff (via hash compare on the snapshot's bunker arrays).

const InvadersConfig := preload("res://scripts/invaders/core/invaders_config.gd")
const InvadersLevel := preload("res://scripts/invaders/core/invaders_level.gd")
const Palette := preload("res://scripts/invaders/invaders_palette.gd")

var _cfg: InvadersConfig
var _level: InvadersLevel
var _snap: Dictionary = {}
var _origins: Array = []   # Array[Vector2]; mirrors state.bunker_origins.


func configure(cfg: InvadersConfig, lvl: InvadersLevel) -> void:
	_cfg = cfg
	_level = lvl
	_compute_origins()
	queue_redraw()


func _compute_origins() -> void:
	_origins = []
	if _cfg == null or _level == null:
		return
	var bunker_world_w: float = _level.bunker_w_cells * _cfg.bunker_cell_w
	var bunker_world_h: float = _level.bunker_h_cells * _cfg.bunker_cell_h
	var total_w: float = _cfg.bunker_count * bunker_world_w
	var gap: float = (_cfg.world_w - total_w) / float(_cfg.bunker_count + 1)
	for i in range(_cfg.bunker_count):
		var ox: float = gap + i * (bunker_world_w + gap)
		var oy: float = _cfg.bunker_y - bunker_world_h * 0.5
		_origins.append(Vector2(ox, oy))


func update_from_snapshot(snap: Dictionary) -> void:
	_snap = snap
	queue_redraw()


func _draw() -> void:
	if _cfg == null or _level == null or _snap.is_empty():
		return
	var bgs: Array = _snap.get("bunkers", [])
	var w: int = _level.bunker_w_cells
	var h: int = _level.bunker_h_cells
	var cw: float = _cfg.bunker_cell_w
	var ch: float = _cfg.bunker_cell_h
	for i in range(min(bgs.size(), _origins.size())):
		var pa: Variant = bgs[i]
		if not (pa is PackedByteArray):
			continue
		var cells: PackedByteArray = pa
		if cells.size() < w * h:
			continue
		var origin: Vector2 = _origins[i]
		for r in range(h):
			for c in range(w):
				if cells[r * w + c] != 1:
					continue
				var x: float = origin.x + c * cw
				var y: float = origin.y + r * ch
				draw_rect(Rect2(Vector2(x, y), Vector2(cw, ch)), Palette.BUNKER, true)
