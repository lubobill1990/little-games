extends RefCounted
## bullet.gd — bullet entities are dict-shaped values; static helpers operate
## on those dicts. Purity contract: no Node, no Engine APIs (only RefCounted
## + math), so this file is unit-testable headless.
##
## Bullet dict shape (kept stable across snapshot):
##   {
##     "owner_kind": String,   # "player" or "enemy"
##     "owner_idx":  int,      # player_idx (0/1) or enemies[] index
##     "x":          int,      # AABB CENTER, sub-px
##     "y":          int,
##     "dir":        int,      # tile_grid.DIR_N/E/S/W (no idle bullets)
##     "speed_sub":  int,      # advance per sub-step
##     "star":       int,      # 0..3; ≥2 can break steel; players only
##     "alive":      bool,     # cleared on consume; pruned by tank_state
##   }
##
## Bullet AABB is HALF_W × HALF_H sub-px (tiny); the small box keeps
## bullet-vs-bullet cancellation localized — two bullets crossing at right
## angles only cancel when their centers actually overlap, not just shared a
## tile during the sub-step. AABB edge-touching == not overlap (per aabb.gd).

const Self := preload("res://scripts/tank/core/bullet.gd")
const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")

# Half-extents in sub-px. Picked small (2) so a normal-speed bullet (4 sub-px)
# advances by more than its own width per sub-step — this is fine because
# tile-collision is checked on the candidate AABB, not via swept testing
# (tunneling cap in tank_config guarantees no skip-over).
const HALF_W: int = 2
const HALF_H: int = 2


## Build a bullet that has just been fired by `tank` (a tank dict). The
## caller decides owner_kind / owner_idx / star / speed; we just position
## it at the muzzle so collision starts cleanly outside the firing tank.
##
## The muzzle is placed one half-tank-extent + one half-bullet-extent ahead
## of the tank center, so the spawn AABB doesn't overlap the firing tank.
static func spawn_from_tank(tank: Dictionary, cfg: TankConfig,
		owner_kind: String, owner_idx: int, speed_sub: int, star: int) -> Dictionary:
	var dir: int = tank["facing"]
	var hx_t: int = (cfg.tank_w_tiles * cfg.tile_size_sub) / 2
	var hy_t: int = (cfg.tank_h_tiles * cfg.tile_size_sub) / 2
	var dx: int = 0
	var dy: int = 0
	match dir:
		TileGrid.DIR_N: dy = -(hy_t + HALF_H)
		TileGrid.DIR_S: dy = (hy_t + HALF_H)
		TileGrid.DIR_E: dx = (hx_t + HALF_W)
		TileGrid.DIR_W: dx = -(hx_t + HALF_W)
	return {
		"owner_kind": owner_kind,
		"owner_idx": owner_idx,
		"x": tank["x"] + dx,
		"y": tank["y"] + dy,
		"dir": dir,
		"speed_sub": speed_sub,
		"star": star,
		"alive": true,
	}


## Advance the bullet one sub-step in its travel direction. Mutates in place.
## Pure motion — collision is resolved separately by tank_state.
static func advance(b: Dictionary) -> void:
	if not b["alive"]:
		return
	var s: int = b["speed_sub"]
	match b["dir"]:
		TileGrid.DIR_N: b["y"] -= s
		TileGrid.DIR_S: b["y"] += s
		TileGrid.DIR_E: b["x"] += s
		TileGrid.DIR_W: b["x"] -= s


## Return the tile coords (col, row) overlapped by the bullet AABB centered
## at (cx, cy). Mirrors tank_entity.tiles_under_tank but with bullet
## half-extents. Negative-coordinate-safe via floor-div so off-grid reads as
## STEEL (which tile_passable_for_bullet treats as a hit → bullet consumed
## at world edge).
static func tiles_under_bullet(cx: int, cy: int, cfg: TankConfig) -> Array:
	var tile: int = cfg.tile_size_sub
	var min_c: int = _floor_div(cx - HALF_W, tile)
	var max_c: int = _floor_div(cx + HALF_W - 1, tile)
	var min_r: int = _floor_div(cy - HALF_H, tile)
	var max_r: int = _floor_div(cy + HALF_H - 1, tile)
	var out: Array = []
	for r in range(min_r, max_r + 1):
		for c in range(min_c, max_c + 1):
			out.append([c, r])
	return out


## True iff the bullet has left the world (any part of its AABB outside the
## 0..world_*_tiles*tile_size_sub box). Caller marks such bullets consumed.
static func out_of_world(b: Dictionary, cfg: TankConfig) -> bool:
	var w_sub: int = cfg.world_w_tiles * cfg.tile_size_sub
	var h_sub: int = cfg.world_h_tiles * cfg.tile_size_sub
	if b["x"] - HALF_W < 0: return true
	if b["x"] + HALF_W > w_sub: return true
	if b["y"] - HALF_H < 0: return true
	if b["y"] + HALF_H > h_sub: return true
	return false


# --- internal ---

static func _floor_div(a: int, b: int) -> int:
	var q: int = a / b
	if (a % b) != 0 and ((a < 0) != (b < 0)):
		q -= 1
	return q
