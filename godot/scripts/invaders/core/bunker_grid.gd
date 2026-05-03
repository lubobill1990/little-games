extends RefCounted
## bunker_grid.gd — pure 2D pixel grid (1 = filled, 0 = empty), row-major.
## Backed by a PackedByteArray for cheap snapshot/restore. No Node, no
## Engine APIs.
##
## Coordinate semantics:
##   - cell coords (cx, cy) are integer column/row indices, 0-based.
##   - The bunker as a whole sits at world position `origin_x, origin_y`
##     (top-left corner). World→cell is the caller's job.
##
## Mutation contract: `clear_cell` and `apply_stamp` set bits to 0 only.
## Bunkers never grow back — bullets erode them monotonically.

const Self := preload("res://scripts/invaders/core/bunker_grid.gd")

var w: int = 0
var h: int = 0
var cells: PackedByteArray = PackedByteArray()


static func create(width: int, height: int, pattern: PackedByteArray) -> Self:
	var g: Self = Self.new()
	g.w = width
	g.h = height
	assert(pattern.size() == width * height, "bunker pattern size mismatch")
	# Copy so subsequent mutations don't aliase the level resource.
	var buf: PackedByteArray = PackedByteArray()
	buf.resize(pattern.size())
	for i in range(pattern.size()):
		buf[i] = pattern[i]
	g.cells = buf
	return g


func get_cell(cx: int, cy: int) -> int:
	if cx < 0 or cx >= w or cy < 0 or cy >= h:
		return 0
	return cells[cy * w + cx]


func clear_cell(cx: int, cy: int) -> void:
	if cx < 0 or cx >= w or cy < 0 or cy >= h:
		return
	cells[cy * w + cx] = 0


## Apply an erosion stamp anchored at (anchor_cx, anchor_cy). The stamp is
## a flat `(stamp_w * stamp_h)` PackedByteArray (1 = clear that cell).
## `anchor_in_stamp` is the (sx, sy) coord WITHIN the stamp that maps to
## the bunker's `(anchor_cx, anchor_cy)`. Out-of-bounds cells are silently
## clipped. Returns the number of bits actually cleared (could be 0 if the
## stamp lands entirely on already-empty cells or off-grid).
func apply_stamp(stamp: PackedByteArray, stamp_w: int, stamp_h: int,
		anchor_cx: int, anchor_cy: int, anchor_sx: int, anchor_sy: int) -> int:
	var cleared: int = 0
	for sy in range(stamp_h):
		for sx in range(stamp_w):
			if stamp[sy * stamp_w + sx] == 0:
				continue
			var bx: int = anchor_cx + (sx - anchor_sx)
			var by: int = anchor_cy + (sy - anchor_sy)
			if bx < 0 or bx >= w or by < 0 or by >= h:
				continue
			if cells[by * w + bx] != 0:
				cells[by * w + bx] = 0
				cleared += 1
	return cleared


## Returns true iff any cell of the bunker overlaps the AABB
## `(cx, cy, hx, hy)` in world coords (origin_x, origin_y is the bunker's
## top-left). This is the broad-phase used by bullet collision: scan the
## intersected cell range, return on first filled cell. The intersect cell
## (cx, cy) is returned via the out_dict if hit.
func aabb_hit(origin_x: float, origin_y: float, cell_w: float, cell_h: float,
		bx: float, by: float, bhx: float, bhy: float, out_dict: Dictionary) -> bool:
	# Convert AABB extent to cell range (inclusive).
	var min_cx: int = int(floor((bx - bhx - origin_x) / cell_w))
	var max_cx: int = int(floor((bx + bhx - origin_x - 0.0001) / cell_w))
	var min_cy: int = int(floor((by - bhy - origin_y) / cell_h))
	var max_cy: int = int(floor((by + bhy - origin_y - 0.0001) / cell_h))
	min_cx = clampi(min_cx, 0, w - 1)
	max_cx = clampi(max_cx, 0, w - 1)
	min_cy = clampi(min_cy, 0, h - 1)
	max_cy = clampi(max_cy, 0, h - 1)
	if min_cx > max_cx or min_cy > max_cy:
		return false
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			if cells[cy * w + cx] != 0:
				out_dict["cx"] = cx
				out_dict["cy"] = cy
				return true
	return false


func snapshot_cells() -> PackedByteArray:
	# Return a copy so callers can't mutate our internal state.
	var out: PackedByteArray = PackedByteArray()
	out.resize(cells.size())
	for i in range(cells.size()):
		out[i] = cells[i]
	return out


static func from_snapshot(width: int, height: int, snap_cells: PackedByteArray) -> Self:
	var g: Self = Self.new()
	g.w = width
	g.h = height
	var buf: PackedByteArray = PackedByteArray()
	buf.resize(snap_cells.size())
	for i in range(snap_cells.size()):
		buf[i] = snap_cells[i]
	g.cells = buf
	return g
