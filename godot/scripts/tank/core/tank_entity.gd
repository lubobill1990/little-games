extends RefCounted
## tank_entity.gd — tank entities are dict-shaped (struct-like) values.
## This module exposes static helpers that operate on those dicts so the
## state object can stay a simple data container.
##
## Tank dict shape (kept stable across snapshot):
##   {
##     "alive":    bool,
##     "kind":     String,    # "player" / "basic" / "fast" / "power" / "armor"
##     "owner":    int,       # 0 = enemy team, 1 = player team
##     "player_idx": int,     # only set when kind == "player" (0 or 1)
##     "x":        int,       # AABB CENTER, sub-px
##     "y":        int,       # AABB CENTER, sub-px
##     "facing":   int,       # tile_grid.DIR_N/E/S/W; preserved when stopped
##     "moving":   bool,      # current sub-step intent
##     "hp":       int,
##     "star":     int,       # 0..3, players only (enemies always 0)
##     "has_ship": bool,
##     "helmet_until_ms": int,
##     "freeze_until_ms": int,  # enemies only
##     "fire_cooldown_until_ms": int,
##     "fire_latched": bool,    # edge-trigger guard for request_fire
##   }
##
## Coordinates: integer sub-pixels. Tank AABB is `tank_w_tiles * tile_size_sub
## × tank_h_tiles * tile_size_sub` (default 32×32). The (x, y) is the
## center, so half-extents are tank_w_tiles*tile_size_sub/2 = 16 on default
## settings. World runs from (0, 0) to (13*16, 13*16) = (208, 208) sub-px.

const Self := preload("res://scripts/tank/core/tank_entity.gd")
const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")
const Aabb := preload("res://scripts/tank/core/aabb.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")


## Build a fresh player tank dict at the spawn tile (top-left tile coord).
## Player tanks are 2×2 tiles; their CENTER is offset (1 tile, 1 tile) from
## the spawn tile's top-left corner.
static func make_player(player_idx: int, spawn_col: int, spawn_row: int,
		cfg: TankConfig) -> Dictionary:
	var hx: int = (cfg.tank_w_tiles * cfg.tile_size_sub) / 2
	var hy: int = (cfg.tank_h_tiles * cfg.tile_size_sub) / 2
	var center_x: int = spawn_col * cfg.tile_size_sub + hx
	var center_y: int = spawn_row * cfg.tile_size_sub + hy
	return {
		"alive": true,
		"kind": "player",
		"owner": 1,
		"player_idx": player_idx,
		"x": center_x,
		"y": center_y,
		"facing": TileGrid.DIR_N,
		"moving": false,
		"hp": 1,
		"star": 0,
		"has_ship": false,
		"helmet_until_ms": 0,
		"freeze_until_ms": 0,
		"fire_cooldown_until_ms": 0,
		"fire_latched": false,
	}


## Half-extents helper (player + enemy tanks share size in v1).
static func half_extents(cfg: TankConfig) -> Array:
	return [
		(cfg.tank_w_tiles * cfg.tile_size_sub) / 2,
		(cfg.tank_h_tiles * cfg.tile_size_sub) / 2,
	]


## Apply the rail-snap rule when intent direction flips between
## perpendicular axes. FC PPU quarter-tile alignment: when the new
## direction differs in axis from facing, snap the OFF-axis coordinate
## to the nearest `rail_snap_sub` boundary so the tank can enter
## 2-wide corridors.
##
## `tank` is mutated in place. Returns the new (snapped) value of the
## off-axis coordinate so tests can assert on it.
static func snap_to_rail(tank: Dictionary, new_dir: int, cfg: TankConfig) -> int:
	var old_dir: int = tank["facing"]
	if not _is_perpendicular_flip(old_dir, new_dir):
		return tank[_off_axis_key(new_dir)]
	var key: String = _off_axis_key(new_dir)
	var v: int = tank[key]
	var snap: int = cfg.rail_snap_sub
	# Round to nearest multiple of snap. ((v + snap/2) / snap) * snap is the
	# usual round-half-up on positive ints; tank coords are always positive
	# in this game so no need for a sign-aware variant.
	var snapped: int = ((v + snap / 2) / snap) * snap
	tank[key] = snapped
	return snapped


## Try to advance `tank` by one sub-step in `tank["facing"]` direction at
## `speed_sub` sub-px. Mutates tank in place. Returns true iff the tank
## actually moved (false → blocked by terrain or other tank).
##
## `other_tanks` is an Array of OTHER live tank dicts — the caller is
## responsible for excluding `tank` itself. Tank-vs-tank uses AABB overlap
## with edge-touching == not overlap (per aabb.gd contract).
static func try_step(tank: Dictionary, speed_sub: int,
		grid: TileGrid, cfg: TankConfig, other_tanks: Array) -> bool:
	if not tank["moving"] or not tank["alive"]:
		return false
	var dir: int = tank["facing"]
	var dx: int = 0
	var dy: int = 0
	match dir:
		TileGrid.DIR_N: dy = -speed_sub
		TileGrid.DIR_S: dy = speed_sub
		TileGrid.DIR_E: dx = speed_sub
		TileGrid.DIR_W: dx = -speed_sub
	var nx: int = tank["x"] + dx
	var ny: int = tank["y"] + dy
	# Tile-collision: check the candidate AABB against every tile it would
	# overlap. If any tile blocks, refuse the move.
	if not _candidate_aabb_passable(nx, ny, grid, cfg, tank["has_ship"]):
		return false
	# Tank-vs-tank: candidate AABB must not overlap any other live tank.
	var hx_hy: Array = half_extents(cfg)
	var hx: int = hx_hy[0]
	var hy: int = hx_hy[1]
	for other in other_tanks:
		if not other["alive"]:
			continue
		if Aabb.overlaps(nx, ny, hx, hy,
				other["x"], other["y"], hx, hy):
			return false
	tank["x"] = nx
	tank["y"] = ny
	return true


## Return all tile coords (col, row) overlapped by the AABB centered at
## (cx, cy) with half-extents matching a tank in the given config. Used
## by tile-collision check and by tests.
##
## Negative-coordinate-safe: integer division in GDScript truncates toward
## zero (so -1/16 = 0, not -1). We use floori-style arithmetic via a
## branch so the off-grid case maps to the intended negative tile index
## (which TileGrid.get_tile then treats as out-of-bounds → STEEL).
static func tiles_under_tank(cx: int, cy: int, cfg: TankConfig) -> Array:
	var hx_hy: Array = half_extents(cfg)
	var hx: int = hx_hy[0]
	var hy: int = hx_hy[1]
	var tile: int = cfg.tile_size_sub
	var min_c: int = _floor_div(cx - hx, tile)
	var max_c: int = _floor_div(cx + hx - 1, tile)
	var min_r: int = _floor_div(cy - hy, tile)
	var max_r: int = _floor_div(cy + hy - 1, tile)
	var out: Array = []
	for r in range(min_r, max_r + 1):
		for c in range(min_c, max_c + 1):
			out.append([c, r])
	return out


# --- internal ---

## Floor division for signed ints. GDScript's `/` truncates toward zero
## (-1 / 16 == 0), which collapses sub-pixel-negative coords onto tile 0
## and silently lets tanks step off the world. floor_div fixes that:
## floor_div(-1, 16) == -1.
static func _floor_div(a: int, b: int) -> int:
	var q: int = a / b
	if (a % b) != 0 and ((a < 0) != (b < 0)):
		q -= 1
	return q

static func _candidate_aabb_passable(cx: int, cy: int,
		grid: TileGrid, cfg: TankConfig, has_ship: bool) -> bool:
	var tiles: Array = tiles_under_tank(cx, cy, cfg)
	for tr in tiles:
		var c: int = tr[0]
		var r: int = tr[1]
		if not grid.tile_passable_for_tank(c, r, has_ship):
			return false
	return true


static func _is_perpendicular_flip(old_dir: int, new_dir: int) -> bool:
	# N/S → vertical axis; E/W → horizontal axis. Axis flip iff the parity
	# (dir % 2) differs.
	if old_dir < 0 or new_dir < 0:
		return false
	return (old_dir & 1) != (new_dir & 1)


static func _off_axis_key(dir: int) -> String:
	# When moving along a vertical axis (N/S), the OFF axis is X.
	# When moving along a horizontal axis (E/W), the OFF axis is Y.
	match dir:
		TileGrid.DIR_N, TileGrid.DIR_S: return "x"
		TileGrid.DIR_E, TileGrid.DIR_W: return "y"
		_: return "x"
