extends RefCounted
## powerup.gd — pure power-up rules. No Node, no Engine APIs. Operates on
## a TankGameState reference (passed as `s`) so effects can touch any
## subsystem (tile grid mutation for shovel, scores untouched for grenade,
## etc.) without needing a callback indirection.
##
## Power-up entity (in s.powerup; null when none on field):
##   {
##     "kind":  String,    # "star" | "grenade" | "helmet" | "timer" | "shovel" | "ship"
##     "col":   int,       # top-left tile coord (always 1×1 tile in v1)
##     "row":   int,
##     "spawned_ms": int,
##   }
##
## Acceptance #11–13 contract:
##   - Killing a `+bonus`-flagged enemy → spawn one power-up at a random
##     EMPTY-or-grass tile (not on the player(s), not on the base).
##   - At most one power-up on the field at a time (FC-faithful: a fresh
##     bonus kill while one is in flight overwrites the previous).
##   - Pickup: any player tank whose 2×2 AABB overlaps the 1-tile pickup
##     box claims it. Tie (both overlap on the same sub-step) → P1 wins.
##   - Helmet does NOT protect the base (acceptance #12c).
##   - Shovel snapshots the 8 base-surrounding tiles at activation and
##     restores them at expiry (acceptance #12e).
##
## RNG: uses TAG_DROP for spawn-tile picking, TAG_PICK for the rare
## tie-break (we resolve P1-wins deterministically without a draw, so
## TAG_PICK is reserved for future variants).

const Self := preload("res://scripts/tank/core/powerup.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")
const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")
const Aabb := preload("res://scripts/tank/core/aabb.gd")

const KINDS: Array = ["star", "grenade", "helmet", "timer", "shovel", "ship"]

# Base-surrounding 8 tile offsets (relative to base top-left). The base sits
# at base_pos = (col, row); we ring it with shovel-bricks. FC layout:
#   . . . .
#   . X X .   (X = brick row above base)
#   . X H .   (where H is the base; X to its left)
#   . . . .
# We treat base as 1 tile, so the 8 surrounding tiles are the standard
# Moore neighborhood.
const SHOVEL_OFFSETS: Array = [
	[-1, -1], [0, -1], [1, -1],
	[-1,  0],          [1,  0],
	[-1,  1], [0,  1], [1,  1],
]


## Spawn a power-up for a bonus-enemy kill. Picks a kind via drop_rng,
## picks a spawn tile via drop_rng among empty-or-grass tiles that aren't
## on a player or the base. Overwrites any existing s.powerup (FC behavior).
##
## Returns the new powerup dict (also written into `s.powerup`).
static func spawn_for_bonus_kill(s, drop_rng: RandomNumberGenerator,
		now_ms: int) -> Dictionary:
	var kind: String = String(KINDS[int(drop_rng.randi() % KINDS.size())])
	# Pick a tile: scan all (col, row), keep candidates passable for tank
	# (no ship), exclude base + player tiles. drop_rng.randi() % candidates
	# gives the choice.
	var candidates: Array = _spawn_candidates(s)
	if candidates.is_empty():
		# Nowhere to put it — silently drop. (Tightly-packed levels only;
		# v1 fixtures always have plenty of room.)
		return {}
	var pick: Array = candidates[int(drop_rng.randi() % candidates.size())] as Array
	var pu: Dictionary = {
		"kind": kind,
		"col": int(pick[0]),
		"row": int(pick[1]),
		"spawned_ms": now_ms,
	}
	s.powerup = pu
	return pu


## Resolve any pickup that happens this sub-step. P1-wins on tie.
## Mutates state if a pickup happens. Returns true iff picked up.
static func try_pickup(s, now_ms: int) -> bool:
	if s.powerup == null:
		return false
	var pu: Dictionary = s.powerup as Dictionary
	var cfg: TankConfig = s.config
	var pcx: int = int(pu["col"]) * cfg.tile_size_sub + cfg.tile_size_sub / 2
	var pcy: int = int(pu["row"]) * cfg.tile_size_sub + cfg.tile_size_sub / 2
	var phx: int = cfg.tile_size_sub / 2
	var phy: int = cfg.tile_size_sub / 2
	var hx: int = (cfg.tank_w_tiles * cfg.tile_size_sub) / 2
	var hy: int = (cfg.tank_h_tiles * cfg.tile_size_sub) / 2
	# Check P1 then P2 — first overlap wins (acceptance #13).
	for pidx in range(s.player_count()):
		var t: Dictionary = s.players[pidx]
		if not t["alive"]:
			continue
		if Aabb.overlaps(pcx, pcy, phx, phy, t["x"], t["y"], hx, hy):
			apply(s, pu, pidx, now_ms)
			s.powerup = null
			return true
	return false


## Apply a power-up's effect to the picking player. Public so tests can
## drive effects directly without staging a pickup overlap.
static func apply(s, pu: Dictionary, picker_idx: int, now_ms: int) -> void:
	var cfg: TankConfig = s.config
	match String(pu["kind"]):
		"star":
			var t: Dictionary = s.players[picker_idx]
			t["star"] = mini(int(t["star"]) + 1, cfg.star_max)
		"grenade":
			# Kill every LIVE enemy. Score not awarded (acceptance #12b).
			for e in s.enemies:
				if e["alive"]:
					e["alive"] = false
					s.wave_state["killed_count"] = int(s.wave_state.get("killed_count", 0)) + 1
		"helmet":
			var t2: Dictionary = s.players[picker_idx]
			t2["helmet_until_ms"] = now_ms + cfg.helmet_pickup_ms
		"timer":
			# Freeze every live enemy for cfg.freeze_pickup_ms. We expose
			# this as state.flags["freeze_until_ms"] so the AI / movement
			# phases can short-circuit while frozen.
			s.flags["freeze_until_ms"] = now_ms + cfg.freeze_pickup_ms
		"shovel":
			# Capture base-surrounding tiles' (tile_id, brick_state) so we
			# can revert at expiry, then upgrade them all to STEEL.
			var prior: Array = []
			for off in SHOVEL_OFFSETS:
				var c: int = int(s.base_pos[0]) + int(off[0])
				var r: int = int(s.base_pos[1]) + int(off[1])
				prior.append([c, r, s.grid.get_tile(c, r), s.grid.get_brick(c, r)])
				s.grid.set_tile(c, r, TileGrid.TILE_STEEL)
				s.grid.set_brick(c, r, TileGrid.BRICK_FULL)
			s.flags["shovel_prior"] = prior
			s.flags["shovel_until_ms"] = now_ms + cfg.shovel_pickup_ms
		"ship":
			var t3: Dictionary = s.players[picker_idx]
			t3["has_ship"] = true


## Called every sub-step from tank_state. Reverts the shovel when its
## timer expires; freeze expiry is checked inline by the AI/movement
## phase via flags["freeze_until_ms"] — no code needed here.
static func tick_expiries(s, now_ms: int) -> bool:
	var changed: bool = false
	var su: int = int(s.flags.get("shovel_until_ms", 0))
	if su > 0 and now_ms >= su:
		var prior: Array = s.flags.get("shovel_prior", []) as Array
		for entry in prior:
			var c: int = int(entry[0])
			var r: int = int(entry[1])
			s.grid.set_tile(c, r, int(entry[2]))
			s.grid.set_brick(c, r, int(entry[3]))
		s.flags["shovel_until_ms"] = 0
		s.flags["shovel_prior"] = []
		changed = true
	return changed


# --- internal ---

static func _spawn_candidates(s) -> Array:
	var cfg: TankConfig = s.config
	var hx: int = (cfg.tank_w_tiles * cfg.tile_size_sub) / 2
	var hy: int = (cfg.tank_h_tiles * cfg.tile_size_sub) / 2
	var out: Array = []
	for r in range(s.grid.H):
		for c in range(s.grid.W):
			var tile: int = s.grid.get_tile(c, r)
			if tile != TileGrid.TILE_EMPTY and tile != TileGrid.TILE_GRASS and tile != TileGrid.TILE_ICE:
				continue
			# Exclude base tile.
			if s.base_pos.size() == 2 and int(s.base_pos[0]) == c and int(s.base_pos[1]) == r:
				continue
			# Exclude player-occupied tiles.
			var pcx: int = c * cfg.tile_size_sub + cfg.tile_size_sub / 2
			var pcy: int = r * cfg.tile_size_sub + cfg.tile_size_sub / 2
			var blocked: bool = false
			for pi in range(s.player_count()):
				var t: Dictionary = s.players[pi]
				if t["alive"] and Aabb.overlaps(pcx, pcy, cfg.tile_size_sub / 2, cfg.tile_size_sub / 2,
						t["x"], t["y"], hx, hy):
					blocked = true
					break
			if blocked:
				continue
			out.append([c, r])
	return out
