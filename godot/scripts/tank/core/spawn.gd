extends RefCounted
## spawn.gd — pure enemy wave queue + spawn-slot picking. No Node, no
## Engine APIs. Operates on TankGameState's wave_state/roster/enemies dicts;
## mutation of state is the caller's responsibility (this module just
## decides "should we spawn now?" and "where?").
##
## Spawn rules (FC-faithful for v1):
##   - The roster supplies the next enemy kind in declaration order.
##   - At most `cfg.max_alive_enemies` live enemies at once. While the
##     cap is full, no spawning attempt happens.
##   - Spawning is gated by `cfg.spawn_interval_ms` measured from the LAST
##     successful spawn attempt (or t=0 for the first one).
##   - Among the enemy spawn slots (E markers), pick one uniformly at
##     random whose 2×2 spawn AABB doesn't overlap any live tank. If every
##     slot is blocked, give up this attempt and re-roll next interval.
##
## RNG: uses `cfg.spawn_rng` (TAG_SPAWN). Slot picks are 1 randi() per
## attempt, regardless of how many slots are blocked, so adding more slots
## in a future level can't shift the fixture for existing levels.
##
## NOTE: spawn-blink animation (cfg.spawn_blink_ms) is a scene concern —
## the core spawns the enemy immediately. Scenes overlay the blink visual
## by querying `last_spawn_ms` from the wave_state.

const Self := preload("res://scripts/tank/core/spawn.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")
const TankEntity := preload("res://scripts/tank/core/tank_entity.gd")
const Aabb := preload("res://scripts/tank/core/aabb.gd")


## Try to spawn the next enemy from the roster. Mutates `enemies`,
## `wave_state` in place. Returns the newly-spawned enemy dict, or null
## if no spawn happened (cap full, interval not elapsed, all slots blocked,
## or roster exhausted).
##
## `players` and `enemies` are passed so we can check spawn-slot occupancy
## (a live tank parked on a spawn slot blocks it).
##
## `wave_state` shape (initialized by tank_state):
##   { spawned_count: int, killed_count: int, queue_index: int,
##     last_spawn_attempt_ms: int }
static func try_spawn(spawn_rng: RandomNumberGenerator, cfg: TankConfig,
		now_ms: int, wave_state: Dictionary, roster: Array,
		enemy_spawn_slots: Array, enemies: Array, players: Array) -> Variant:
	# Roster exhaustion: nothing left to spawn.
	var qi: int = int(wave_state.get("queue_index", 0))
	if qi >= roster.size():
		return null
	# Cap on live enemies.
	var alive: int = 0
	for e in enemies:
		if e["alive"]:
			alive += 1
	if alive >= cfg.max_alive_enemies:
		return null
	# Interval gate (relative to last attempt time, NOT last successful
	# spawn — keeps the cadence visible even when slots block).
	var last_attempt: int = int(wave_state.get("last_spawn_attempt_ms", -cfg.spawn_interval_ms))
	if now_ms - last_attempt < cfg.spawn_interval_ms:
		return null
	wave_state["last_spawn_attempt_ms"] = now_ms
	# Pick a slot.
	if enemy_spawn_slots.is_empty():
		return null
	var slot_idx: int = int(spawn_rng.randi() % enemy_spawn_slots.size())
	var slot: Array = enemy_spawn_slots[slot_idx] as Array
	if not _slot_clear(slot[0] as int, slot[1] as int, cfg, enemies, players):
		# Try the remaining slots in a deterministic forward sweep so a
		# crowded board still spawns when SOME slot is free. Sweep order
		# starts at slot_idx + 1 to keep the bias toward the rolled slot.
		var found: bool = false
		for offset in range(1, enemy_spawn_slots.size()):
			var alt_idx: int = (slot_idx + offset) % enemy_spawn_slots.size()
			var alt: Array = enemy_spawn_slots[alt_idx] as Array
			if _slot_clear(alt[0] as int, alt[1] as int, cfg, enemies, players):
				slot_idx = alt_idx
				slot = alt
				found = true
				break
		if not found:
			return null
	# Spawn. Roster entries are dicts: {kind: String, bonus: bool}.
	var entry: Dictionary = roster[qi] as Dictionary
	var kind: String = String(entry.get("kind", "basic"))
	var bonus: bool = bool(entry.get("bonus", false))
	var enemy: Dictionary = TankEntity.make_enemy(kind, slot[0] as int, slot[1] as int, bonus, cfg)
	enemy["last_decision_ms"] = now_ms  # AI starts its recheck clock here.
	enemies.append(enemy)
	wave_state["queue_index"] = qi + 1
	wave_state["spawned_count"] = int(wave_state.get("spawned_count", 0)) + 1
	return enemy


# --- internal ---

## True iff the 2×2 spawn AABB at (col, row) is clear of every live tank.
## Player tanks parked on a spawn slot block it; enemies are checked for
## the obvious self-overlap case.
static func _slot_clear(col: int, row: int, cfg: TankConfig,
		enemies: Array, players: Array) -> bool:
	var hx: int = (cfg.tank_w_tiles * cfg.tile_size_sub) / 2
	var hy: int = (cfg.tank_h_tiles * cfg.tile_size_sub) / 2
	var cx: int = col * cfg.tile_size_sub + hx
	var cy: int = row * cfg.tile_size_sub + hy
	for p in players:
		if not p["alive"]:
			continue
		if Aabb.overlaps(cx, cy, hx, hy, p["x"], p["y"], hx, hy):
			return false
	for e in enemies:
		if not e["alive"]:
			continue
		if Aabb.overlaps(cx, cy, hx, hy, e["x"], e["y"], hx, hy):
			return false
	return true
