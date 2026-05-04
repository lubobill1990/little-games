extends RefCounted
## tile_grid.gd — pure 13×13 tile grid + per-brick half-erosion state.
## No Node, no Engine APIs.
##
## Storage: `tiles` is a PackedByteArray of 169 entries, each a tile id
## (see TILE_* constants below). `bricks` is a PackedByteArray of 169
## entries indexed identically; the value is a brick erosion state
## (see BRICK_* constants) and is meaningful only where `tiles[i] == TILE_BRICK`.
##
## Brick erosion (PRD: half-brick — 4 enum half-states + full + destroyed):
##   FULL          — intact
##   TOP_GONE      — top half cleared (south-facing bullet hit it from below)
##   BOTTOM_GONE   — bottom half cleared (north-facing bullet hit it from above)
##   LEFT_GONE     — left half cleared (east-facing bullet hit from right)
##   RIGHT_GONE    — right half cleared (west-facing bullet hit from left)
##   DESTROYED     — fully cleared; passable thereafter
## Per Dev plan §Risks: per-quadrant erosion deferred to v2.
##
## Passability semantics (per PRD §Terrain):
##   Tank (no ship): empty/grass/ice  passable; brick/steel/water/base block.
##   Tank (with ship): + water passable; brick/steel/base still block.
##   Bullet: empty/water/grass/ice passable; brick/steel/base block.
## (`P`/`E` markers are placed on empty terrain at parse time; we model them
##  as TILE_EMPTY at runtime and remember spawn locations separately.)

const Self := preload("res://scripts/tank/core/tile_grid.gd")

const TILE_EMPTY: int = 0
const TILE_BRICK: int = 1
const TILE_STEEL: int = 2
const TILE_WATER: int = 3
const TILE_GRASS: int = 4
const TILE_ICE: int = 5
const TILE_BASE: int = 6   # 'H' / eagle

const BRICK_FULL: int = 0
const BRICK_TOP_GONE: int = 1
const BRICK_BOTTOM_GONE: int = 2
const BRICK_LEFT_GONE: int = 3
const BRICK_RIGHT_GONE: int = 4
const BRICK_DESTROYED: int = 5

# Direction enum (matches TankGameState.set_player_intent contract):
# 0=N, 1=E, 2=S, 3=W. -1 = stop / invalid.
const DIR_N: int = 0
const DIR_E: int = 1
const DIR_S: int = 2
const DIR_W: int = 3

const W: int = 13
const H: int = 13

var tiles: PackedByteArray = PackedByteArray()
var bricks: PackedByteArray = PackedByteArray()


## Build a grid from a PackedStringArray of 13 13-char rows. Player- and
## enemy-spawn markers ('P', 'E') are written as TILE_EMPTY in the grid;
## the caller (level loader / TankGameState) must keep their coords
## separately via tank_level.find_*_spawns().
static func from_rows(rows: PackedStringArray) -> Self:
	assert(rows.size() == H, "tile_grid: expected %d rows, got %d" % [H, rows.size()])
	var g: Self = Self.new()
	g.tiles = PackedByteArray()
	g.tiles.resize(W * H)
	g.bricks = PackedByteArray()
	g.bricks.resize(W * H)
	for r in range(H):
		var row: String = rows[r]
		assert(row.length() == W, "tile_grid: row %d width %d != %d" % [r, row.length(), W])
		for c in range(W):
			var t: int = _char_to_tile(row[c])
			g.tiles[r * W + c] = t
			# All bricks start FULL; non-brick cells leave the byte at 0
			# (BRICK_FULL) by virtue of resize, which is harmless because
			# erosion is only consulted when tiles[i] == TILE_BRICK.
			if t == TILE_BRICK:
				g.bricks[r * W + c] = BRICK_FULL
	return g


## Restore a grid from snapshot bytes (must be 169 entries each).
static func from_snapshot(snap_tiles: PackedByteArray, snap_bricks: PackedByteArray) -> Self:
	assert(snap_tiles.size() == W * H, "tile_grid: snap_tiles size %d" % snap_tiles.size())
	assert(snap_bricks.size() == W * H, "tile_grid: snap_bricks size %d" % snap_bricks.size())
	var g: Self = Self.new()
	g.tiles = PackedByteArray()
	g.tiles.resize(W * H)
	g.bricks = PackedByteArray()
	g.bricks.resize(W * H)
	for i in range(W * H):
		g.tiles[i] = snap_tiles[i]
		g.bricks[i] = snap_bricks[i]
	return g


# --- accessors ---

func get_tile(c: int, r: int) -> int:
	if c < 0 or c >= W or r < 0 or r >= H:
		return TILE_STEEL  # off-grid acts as solid steel for collision purposes
	return tiles[r * W + c]


func get_brick(c: int, r: int) -> int:
	if c < 0 or c >= W or r < 0 or r >= H:
		return BRICK_FULL
	return bricks[r * W + c]


func set_tile(c: int, r: int, t: int) -> void:
	if c < 0 or c >= W or r < 0 or r >= H:
		return
	tiles[r * W + c] = t


func set_brick(c: int, r: int, b: int) -> void:
	if c < 0 or c >= W or r < 0 or r >= H:
		return
	bricks[r * W + c] = b


# --- passability ---

## True iff a tank can occupy this tile.
func tile_passable_for_tank(c: int, r: int, has_ship: bool) -> bool:
	var t: int = get_tile(c, r)
	match t:
		TILE_EMPTY, TILE_GRASS, TILE_ICE:
			return true
		TILE_WATER:
			return has_ship
		TILE_BRICK:
			# A brick is "destroyed" only when its erosion state is BRICK_DESTROYED.
			return get_brick(c, r) == BRICK_DESTROYED
		TILE_STEEL, TILE_BASE:
			return false
		_:
			return false


## True iff a bullet can pass through this tile (post-collision-check; this
## helper says nothing about erosion or destruction. Bullet-vs-tile is
## resolved by the bullet phase in tick().).
func tile_passable_for_bullet(c: int, r: int) -> bool:
	var t: int = get_tile(c, r)
	match t:
		TILE_EMPTY, TILE_WATER, TILE_GRASS, TILE_ICE:
			return true
		TILE_BRICK:
			return get_brick(c, r) == BRICK_DESTROYED
		TILE_STEEL, TILE_BASE:
			return false
		_:
			return false


# --- erosion ---

## Apply a bullet-hit to a brick at (c, r) coming from `from_dir`
## (the bullet's TRAVEL direction, e.g. a north-traveling bullet hits the
## brick from below → eats the BOTTOM half first).
##
## Returns true iff the brick was fully destroyed by this hit (caller can
## then mark the bullet consumed regardless — bricks always consume the
## bullet on contact per PRD).
func erode_brick(c: int, r: int, bullet_travel_dir: int) -> bool:
	if get_tile(c, r) != TILE_BRICK:
		return false
	var b: int = get_brick(c, r)
	if b == BRICK_DESTROYED:
		return false
	# Map bullet TRAVEL direction → which half is eaten on first hit.
	# A north-traveling bullet (going up) strikes the brick from BELOW,
	# so it eats the BOTTOM half. Opposite holds for south.
	var eat_half: int = -1
	match bullet_travel_dir:
		DIR_N:
			eat_half = BRICK_BOTTOM_GONE
		DIR_S:
			eat_half = BRICK_TOP_GONE
		DIR_E:
			eat_half = BRICK_LEFT_GONE
		DIR_W:
			eat_half = BRICK_RIGHT_GONE
	# If the brick is already in a half-state, the second hit destroys it
	# regardless of which half remains (per PRD: half-brick captures the
	# FC feel; per-quadrant deferred).
	if b == BRICK_FULL:
		set_brick(c, r, eat_half)
		return false
	# Already half-eroded → destroy.
	set_brick(c, r, BRICK_DESTROYED)
	set_tile(c, r, TILE_EMPTY)  # passable thereafter
	return true


## Star ≥ 2 bullet vs steel: destroys the whole tile. Returns true iff
## the steel tile was destroyed (caller consumes the bullet either way).
func break_steel(c: int, r: int) -> bool:
	if get_tile(c, r) != TILE_STEEL:
		return false
	set_tile(c, r, TILE_EMPTY)
	return true


# --- snapshot ---

func snapshot_tiles() -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(tiles.size())
	for i in range(tiles.size()):
		out[i] = tiles[i]
	return out


func snapshot_bricks() -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(bricks.size())
	for i in range(bricks.size()):
		out[i] = bricks[i]
	return out


# --- internal ---

static func _char_to_tile(ch: String) -> int:
	match ch:
		".": return TILE_EMPTY
		"B": return TILE_BRICK
		"S": return TILE_STEEL
		"W": return TILE_WATER
		"G": return TILE_GRASS
		"I": return TILE_ICE
		"H": return TILE_BASE
		"P", "E": return TILE_EMPTY  # spawn markers occupy empty terrain
		_:
			# Unknown chars should have been rejected by parse_tiles already;
			# fall back to empty rather than crashing.
			return TILE_EMPTY
