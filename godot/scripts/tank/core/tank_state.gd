extends RefCounted
## TankGameState — pure rules for the FC Battle City clone. No Node, no
## signals. tick() returns bool ("visible state changed"); scene-side
## observes via snapshot diff (per CLAUDE.md §5 architecture rule).
##
## v1 schema (`SCHEMA_VERSION = 1`):
##   Implemented in this PR — players, movement, rail-snap, level + roster
##   loading, snapshot/restore. Bullets, AI/spawning, power-ups, win/lose
##   land in the same PR's later commits per #52 Dev plan §Commit sequence.
##
## Reserved snapshot fields populated empty in v1:
##   - effects: []   visual events queue, future scene wiring
##   - vs_mode: null PvP mode toggle (out of scope for #52)
##   - bullets, enemies, powerup, wave_state, scores updates: written by
##     subsequent commits inside this PR but kept in the snapshot now so
##     v1 fixtures don't break later.

const Self := preload("res://scripts/tank/core/tank_state.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")
const TankLevel := preload("res://scripts/tank/core/tank_level.gd")
const TankEntity := preload("res://scripts/tank/core/tank_entity.gd")
const TileGrid := preload("res://scripts/tank/core/tile_grid.gd")
const SubRng := preload("res://scripts/tank/core/sub_rng.gd")
const Bullet := preload("res://scripts/tank/core/bullet.gd")
const Aabb := preload("res://scripts/tank/core/aabb.gd")
const Ai := preload("res://scripts/tank/core/ai.gd")
const Spawn := preload("res://scripts/tank/core/spawn.gd")
const Powerup := preload("res://scripts/tank/core/powerup.gd")

const SCHEMA_VERSION: int = 1


# --- config / level ---
var config: TankConfig
var grid: TileGrid
var roster: Array = []                # [{kind: String, bonus: bool}, …]
var base_pos: Array = []              # [col, row] of the eagle
var enemy_spawn_slots: Array = []     # [[col, row], …] in declaration order
var player_spawn_slots: Array = []    # [[col, row], …]; size == player_count

# --- entities ---
var players: Array = []               # length == _player_count; each is a TankEntity dict
var enemies: Array = []               # populated by AI commit; reserved here
var bullets: Array = []               # populated by bullet commit; reserved here

# --- power-up state (reserved; populated by power-up commit) ---
var powerup: Variant = null

# --- wave / score ---
var wave_state: Dictionary = {
	"spawned_count": 0,
	"killed_count": 0,
	"queue_index": 0,
	"last_spawn_attempt_ms": -1000000,  # ensure first attempt is always due
}
var scores: Array = [0, 0]            # always length 2; idx >= player_count is unused
var lives_arr: Array = [0, 0]         # same shape as scores

# --- flags ---
var flags: Dictionary = {
	"shovel_until_ms": 0,
	"shovel_prior": [],
	"freeze_until_ms": 0,
}

# --- time ---
var now_ms: int = 0
var last_tick_ms: int = 0
var initialized_clock: bool = false
var sub_step_accum_ms: int = 0

# --- RNGs ---
var _master_seed: int = 0
var _player_count: int = 1
var _spawn_rng: RandomNumberGenerator
var _ai_target_rng: RandomNumberGenerator
var _ai_fire_rng: RandomNumberGenerator
var _drop_rng: RandomNumberGenerator
var _pick_rng: RandomNumberGenerator


# ---------------- Construction ----------------

## Create a fresh game state. Returns null + push_error on:
##   - tunneling cap violation (config.tunneling_ok() == false)
##   - level parse failure (forwarded from TankLevel.parse_level)
##   - player_count out of {1, 2}
static func create(seed: int, level_tiles: String, level_roster: String,
		player_count: int = 1, cfg: TankConfig = null) -> Self:
	if player_count != 1 and player_count != 2:
		push_error("TankGameState.create: player_count must be 1 or 2 (got %d)" % player_count)
		return null
	var c: TankConfig = cfg if cfg != null else TankConfig.new()
	if not c.tunneling_ok():
		push_error("TankGameState.create: tunneling cap violated. " +
			"Reduce bullet_speed_*_sub or grow tile_size_sub so " +
			"max(bullet_speed) < min(tile_size_sub/2, tank_h_tiles*tile_size_sub).")
		return null
	var parsed: Variant = TankLevel.parse_level(level_tiles, level_roster, player_count)
	if parsed == null:
		# parse_level already pushed a specific error; surface a wrap-up
		# so a stack trace bubbles up too.
		push_error("TankGameState.create: level parse failed (see prior error)")
		return null
	var s: Self = Self.new()
	s.config = c
	s._master_seed = seed
	s._player_count = player_count
	# Sub-RNGs split via XOR-tag (see sub_rng.gd). Each consumer is isolated.
	s._spawn_rng = SubRng.make(seed, SubRng.TAG_SPAWN)
	s._ai_target_rng = SubRng.make(seed, SubRng.TAG_AI_TARGET)
	s._ai_fire_rng = SubRng.make(seed, SubRng.TAG_AI_FIRE)
	s._drop_rng = SubRng.make(seed, SubRng.TAG_DROP)
	s._pick_rng = SubRng.make(seed, SubRng.TAG_PICK)
	# Build tile grid from parsed rows.
	var d: Dictionary = parsed as Dictionary
	var rows: PackedStringArray = d["tiles"] as PackedStringArray
	s.grid = TileGrid.from_rows(rows)
	s.roster = d["roster"] as Array
	s.base_pos = TankLevel.find_base(rows)
	s.enemy_spawn_slots = TankLevel.find_enemy_spawns(rows)
	# Players.
	s.player_spawn_slots = []
	if d["p1"] is Array and (d["p1"] as Array).size() == 2:
		s.player_spawn_slots.append(d["p1"])
	if player_count == 2 and d["p2"] is Array and (d["p2"] as Array).size() == 2:
		s.player_spawn_slots.append(d["p2"])
	s.players = []
	for idx in range(player_count):
		var sp: Array = s.player_spawn_slots[idx] as Array
		var t: Dictionary = TankEntity.make_player(idx, sp[0] as int, sp[1] as int, c)
		s.players.append(t)
	# Lives.
	for idx in range(player_count):
		s.lives_arr[idx] = c.player_lives_start
	return s


# ---------------- Public API ----------------

## Set a player's movement intent.
##   dir == -1: stop (clear `moving`); preserve current `facing`.
##   dir ∈ {0, 1, 2, 3}: set `facing` to dir, mark `moving = true`. If the
##     new direction is perpendicular to the current facing, apply rail-snap
##     so the tank can enter narrow corridors.
##   Any other value: no-op.
##   player_idx out of range: no-op (1P-mode call to player_idx == 1 is silent).
func set_player_intent(player_idx: int, dir: int) -> void:
	if player_idx < 0 or player_idx >= _player_count:
		return
	var tank: Dictionary = players[player_idx]
	if not tank["alive"]:
		return
	if dir == -1:
		tank["moving"] = false
		return
	if dir < 0 or dir > 3:
		return
	# Apply rail-snap BEFORE updating facing so snap_to_rail can detect
	# perpendicular flip correctly.
	TankEntity.snap_to_rail(tank, dir, config)
	tank["facing"] = dir
	tank["moving"] = true


## Edge-triggered fire request. Returns true iff accepted (cooldown
## elapsed, player alive, latch released, and the player has fewer live
## bullets than the per-star cap). The bullet is spawned at the tank's
## muzzle and added to `bullets` immediately so the within-sub-step
## resolution order in `_step_one` can see it on the very next tick.
func request_fire(player_idx: int) -> bool:
	if player_idx < 0 or player_idx >= _player_count:
		return false
	var tank: Dictionary = players[player_idx]
	if not tank["alive"]:
		return false
	if tank["fire_latched"]:
		return false  # holding the button is not autofire
	if now_ms < tank["fire_cooldown_until_ms"]:
		return false
	# Max-bullets-on-screen rule: star ≥ 3 → 2 bullets; otherwise 1.
	var star: int = int(tank["star"])
	var max_bullets: int = config.star_max_bullets_l3 if star >= 3 else 1
	var live: int = 0
	for b in bullets:
		if b["alive"] and b["owner_kind"] == "player" and int(b["owner_idx"]) == player_idx:
			live += 1
	if live >= max_bullets:
		return false
	tank["fire_latched"] = true
	tank["fire_cooldown_until_ms"] = now_ms + config.fire_cooldown_ms
	# Star ≥ 1 → fast bullet (per acceptance #4-adjacent + tank_config notes).
	var speed: int = config.bullet_speed_fast_sub if star >= 1 else config.bullet_speed_normal_sub
	bullets.append(Bullet.spawn_from_tank(tank, config, "player", player_idx, speed, star))
	return true


## Release the fire latch (caller signals "button no longer held").
## Required so request_fire can succeed again on next press.
func release_fire(player_idx: int) -> void:
	if player_idx < 0 or player_idx >= _player_count:
		return
	var tank: Dictionary = players[player_idx]
	tank["fire_latched"] = false


## Advance simulation up to `now_ms`. Returns true iff visible state
## changed (movement, kills, pickups, etc.).
##
## Sub-step model: catch up in `config.sub_step_ms` chunks (default 16 ms),
## capped by `config.max_sub_steps_per_tick`. This commit only resolves
## player-tank movement; subsequent commits add bullets, AI, power-ups,
## win/lose checks.
func tick(t_ms: int) -> bool:
	if not initialized_clock:
		last_tick_ms = t_ms
		now_ms = t_ms
		initialized_clock = true
		return false
	if t_ms <= last_tick_ms:
		return false
	var dt: int = t_ms - last_tick_ms
	last_tick_ms = t_ms
	sub_step_accum_ms += dt
	var sub_dt: int = config.sub_step_ms
	var changed: bool = false
	var max_sub: int = config.max_sub_steps_per_tick
	var n: int = 0
	while sub_step_accum_ms >= sub_dt and n < max_sub:
		sub_step_accum_ms -= sub_dt
		now_ms += sub_dt
		if _step_one(now_ms):
			changed = true
		n += 1
	# If we hit the cap, drop the remainder so we don't spiral on a paused
	# tab returning with a multi-second dt.
	if n >= max_sub:
		sub_step_accum_ms = 0
	return changed


## Set `last_tick_ms` directly without stepping. Used by tests + scene
## reload to align the clock to the engine timeline. After this call,
## tick(t + sub_step_ms) advances exactly one sub-step.
func set_last_tick(t_ms: int) -> void:
	last_tick_ms = t_ms
	now_ms = t_ms
	initialized_clock = true
	sub_step_accum_ms = 0


# --- queries ---

func is_game_over() -> bool:
	# Either the base has been destroyed (acceptance #15a), or every player
	# is permanently out of lives (1P: P1 lives==0 with no respawn pending;
	# 2P co-op: both players' lives==0).
	if base_pos.size() == 2 and grid.get_tile(int(base_pos[0]), int(base_pos[1])) != TileGrid.TILE_BASE:
		return true
	for idx in range(_player_count):
		# Alive on the field OR has lives left OR respawn timer pending.
		if players[idx]["alive"]:
			return false
		if lives_arr[idx] > 0:
			return false
		if int(players[idx].get("respawn_at_ms", 0)) > now_ms:
			return false
	return true


func is_level_clear() -> bool:
	# Acceptance #14: clearing all enemies with one enemy bullet still alive
	# does NOT count as cleared until that bullet expires/hits. So:
	#   - all roster entries spawned, AND
	#   - no live enemy on the field, AND
	#   - no enemy bullet in flight.
	if int(wave_state.get("queue_index", 0)) < roster.size():
		return false
	for e in enemies:
		if e["alive"]:
			return false
	for b in bullets:
		if b["alive"] and b["owner_kind"] == "enemy":
			return false
	return true


func score(player_idx: int) -> int:
	if player_idx < 0 or player_idx >= _player_count:
		return 0
	return scores[player_idx]


func lives(player_idx: int) -> int:
	if player_idx < 0 or player_idx >= _player_count:
		return 0
	return lives_arr[player_idx]


func player_count() -> int:
	return _player_count


# ---------------- Snapshot ----------------

func snapshot() -> Dictionary:
	# Players: deep-copy each tank dict so the caller can't mutate ours.
	var pl: Array = []
	for t in players:
		pl.append((t as Dictionary).duplicate(true))
	return {
		"version": SCHEMA_VERSION,
		"player_count": _player_count,
		"tiles": grid.snapshot_tiles(),
		"bricks": grid.snapshot_bricks(),
		"players": pl,
		"enemies": enemies.duplicate(true),
		"bullets": bullets.duplicate(true),
		"powerup": powerup,
		"wave_state": wave_state.duplicate(true),
		"scores": scores.duplicate(true),
		"lives_arr": lives_arr.duplicate(true),
		"now_ms": now_ms,
		"last_tick_ms": last_tick_ms,
		"sub_step_accum_ms": sub_step_accum_ms,
		"initialized_clock": initialized_clock,
		"flags": flags.duplicate(true),
		"rng_states": _rng_state_snapshot(),
		"roster": roster.duplicate(true),
		"base_pos": base_pos.duplicate(true),
		"enemy_spawn_slots": enemy_spawn_slots.duplicate(true),
		"player_spawn_slots": player_spawn_slots.duplicate(true),
		"master_seed": _master_seed,
		# Reserved (empty/null in v1).
		"effects": [],
		"vs_mode": null,
	}


## Rebuild bit-equal state from a v1 snapshot. Caller is responsible for
## passing in a valid Dictionary; we don't try to migrate older versions
## (none exist).
static func from_snapshot(snap: Dictionary) -> Self:
	if int(snap.get("version", -1)) != SCHEMA_VERSION:
		push_error("TankGameState.from_snapshot: unsupported version %s" % snap.get("version", "?"))
		return null
	var s: Self = Self.new()
	# Config is recreated with defaults; tunable fields would live in
	# snap["config_overrides"] in a future schema. For v1 we always restore
	# under the current default config.
	s.config = TankConfig.new()
	s._player_count = int(snap["player_count"])
	s._master_seed = int(snap["master_seed"])
	# Re-seed sub-RNGs from master seed, then advance them to the recorded
	# state (state is captured as RandomNumberGenerator.state, an int).
	var rng_states: Dictionary = snap["rng_states"] as Dictionary
	s._spawn_rng = _restore_rng(s._master_seed, SubRng.TAG_SPAWN, int(rng_states["spawn"]))
	s._ai_target_rng = _restore_rng(s._master_seed, SubRng.TAG_AI_TARGET, int(rng_states["ai_target"]))
	s._ai_fire_rng = _restore_rng(s._master_seed, SubRng.TAG_AI_FIRE, int(rng_states["ai_fire"]))
	s._drop_rng = _restore_rng(s._master_seed, SubRng.TAG_DROP, int(rng_states["drop"]))
	s._pick_rng = _restore_rng(s._master_seed, SubRng.TAG_PICK, int(rng_states["pick"]))
	# Tile grid.
	s.grid = TileGrid.from_snapshot(snap["tiles"] as PackedByteArray, snap["bricks"] as PackedByteArray)
	# Entities + arrays.
	s.players = []
	for t in (snap["players"] as Array):
		s.players.append((t as Dictionary).duplicate(true))
	s.enemies = (snap["enemies"] as Array).duplicate(true)
	s.bullets = (snap["bullets"] as Array).duplicate(true)
	s.powerup = snap["powerup"]
	s.wave_state = (snap["wave_state"] as Dictionary).duplicate(true)
	s.scores = (snap["scores"] as Array).duplicate(true)
	s.lives_arr = (snap["lives_arr"] as Array).duplicate(true)
	s.flags = (snap["flags"] as Dictionary).duplicate(true)
	s.roster = (snap["roster"] as Array).duplicate(true)
	s.base_pos = (snap["base_pos"] as Array).duplicate(true)
	s.enemy_spawn_slots = (snap["enemy_spawn_slots"] as Array).duplicate(true)
	s.player_spawn_slots = (snap["player_spawn_slots"] as Array).duplicate(true)
	# Time.
	s.now_ms = int(snap["now_ms"])
	s.last_tick_ms = int(snap["last_tick_ms"])
	s.sub_step_accum_ms = int(snap["sub_step_accum_ms"])
	s.initialized_clock = bool(snap["initialized_clock"])
	return s


# ---------------- internal ----------------

## Resolve one sub-step. Returns true iff visible state changed.
##
## Order (per acceptance #6):
##   1. spawn (try one new enemy from the roster if cap + interval allow)
##   2. movement (player tanks; enemy tanks: AI decides direction first)
##   3. enemy fire roll (per-sub-step probability; cooldown enforced)
##   4. bullet motion (advance every live bullet by speed_sub)
##   5. bullet-vs-bullet mutual cancel (player↔enemy AABB overlap)
##   6. bullet-vs-tank (enemy bullets damage players; player bullets damage
##      enemies; teammates immune per acceptance #9 — currently a no-op
##      because enemies[] is empty until the AI commit, and same-owner
##      bullets ignore their own tanks)
##   7. bullet-vs-tile (brick erosion or steel break by star ≥ 2; bullet
##      consumed on contact regardless)
##   8. bullet-vs-base (any bullet hit ends the game; lose handled in the
##      win/lose commit — for now we just clear the base tile + consume)
##   9. prune dead bullets / dead enemies
##
## Iteration is `(owner_kind, owner_idx, bullet_idx)` with player < enemy,
## so resolution is deterministic across runs and snapshot-replays.
func _step_one(t_ms: int) -> bool:
	var changed: bool = false
	# (0) respawn check. If a dead player's respawn_at_ms has elapsed, put
	# them back at their spawn tile with a fresh helmet. Per acceptance #16,
	# any enemy whose AABB overlaps the spawn tile at the moment of respawn
	# is destroyed silently (no score awarded).
	for pidx0 in range(_player_count):
		var pt0: Dictionary = players[pidx0]
		if pt0["alive"]:
			continue
		if lives_arr[pidx0] <= 0:
			continue
		if t_ms < int(pt0["respawn_at_ms"]):
			continue
		TankEntity.respawn_player(pt0, config, t_ms)
		# Acceptance #16: kill any enemy parked on the spawn AABB.
		var phx: int = (config.tank_w_tiles * config.tile_size_sub) / 2
		var phy: int = (config.tank_h_tiles * config.tile_size_sub) / 2
		for e0 in enemies:
			if not e0["alive"]:
				continue
			if Aabb.overlaps(pt0["x"], pt0["y"], phx, phy,
					e0["x"], e0["y"], phx, phy):
				e0["alive"] = false
				wave_state["killed_count"] = int(wave_state.get("killed_count", 0)) + 1
				# No score award (acceptance #16).
		changed = true
	# (1) spawn.
	var spawned: Variant = Spawn.try_spawn(_spawn_rng, config, t_ms,
			wave_state, roster, enemy_spawn_slots, enemies, players)
	if spawned != null:
		changed = true
	# (2a) player movement.
	for idx in range(_player_count):
		var tank: Dictionary = players[idx] as Dictionary
		if not tank["alive"] or not tank["moving"]:
			continue
		var others: Array = []
		for jdx in range(_player_count):
			if jdx == idx:
				continue
			others.append(players[jdx])
		for e in enemies:
			others.append(e)
		var moved: bool = TankEntity.try_step(tank,
				config.tank_speed_player_sub, grid, config, others)
		if moved:
			changed = true
	# (2b) enemy AI decision + movement.
	# Freeze gate: when flags["freeze_until_ms"] > t_ms, enemies don't
	# move or change facing — but the RNG draws still happen so the
	# determinism contract (acceptance #10/#19) holds across frozen runs.
	var frozen: bool = t_ms < int(flags.get("freeze_until_ms", 0))
	for ei in range(enemies.size()):
		var en: Dictionary = enemies[ei]
		if not en["alive"]:
			continue
		var new_dir: int = Ai.decide_dir(_ai_target_rng, en, base_pos, config, t_ms)
		if not frozen and new_dir >= 0:
			TankEntity.snap_to_rail(en, new_dir, config)
			en["facing"] = new_dir
			en["moving"] = true
			changed = true
		if frozen:
			continue
		# Build "others" excluding self.
		var e_others: Array = []
		for pi2 in range(_player_count):
			e_others.append(players[pi2])
		for ej in range(enemies.size()):
			if ej == ei:
				continue
			e_others.append(enemies[ej])
		var espeed: int = config.tank_speed_fast_sub if en["kind"] == "fast" else config.tank_speed_basic_sub
		var emoved: bool = TankEntity.try_step(en, espeed, grid, config, e_others)
		if emoved:
			changed = true
	# (3) enemy fire roll (1 randf per live enemy per sub-step — pinned for
	# determinism, regardless of cooldown / freeze outcome).
	for ei2 in range(enemies.size()):
		var en2: Dictionary = enemies[ei2]
		if not en2["alive"]:
			continue
		var want_fire: bool = Ai.should_fire(_ai_fire_rng, config)
		if frozen:
			continue  # RNG already drawn; just don't act.
		if not want_fire:
			continue
		if t_ms < int(en2["fire_cooldown_until_ms"]):
			continue
		# 1 enemy bullet on screen per enemy (FC standard for basic enemies).
		var live: int = 0
		for b0 in bullets:
			if b0["alive"] and b0["owner_kind"] == "enemy" and int(b0["owner_idx"]) == ei2:
				live += 1
		if live >= 1:
			continue
		en2["fire_cooldown_until_ms"] = t_ms + config.fire_cooldown_ms
		# Power-enemy bullets are fast (star=1 sentinel reuses bullet.speed lookup).
		var espeed_bullet: int = config.bullet_speed_fast_sub if en2["kind"] == "power" else config.bullet_speed_normal_sub
		bullets.append(Bullet.spawn_from_tank(en2, config, "enemy", ei2, espeed_bullet, 0))
		changed = true
	# (3b) power-up pickup + expiry. Pickup before bullet-vs-tank so a player
	# walking onto a power-up tile can still take damage from a bullet on the
	# SAME sub-step (the pickup happens at movement time; bullet phase is
	# unaffected). Expiry runs first so a shovel that just expired doesn't
	# block a bullet that was about to hit the base.
	if Powerup.tick_expiries(self, t_ms):
		changed = true
	if Powerup.try_pickup(self, t_ms):
		changed = true
	if bullets.is_empty():
		return changed
	# (4) advance bullets. Out-of-world → consume immediately.
	for b in bullets:
		if not b["alive"]:
			continue
		Bullet.advance(b)
		if Bullet.out_of_world(b, config):
			b["alive"] = false
			changed = true
	var order: Array = _bullet_iteration_order()
	# (5) bullet-vs-bullet mutual cancel.
	for i in range(order.size()):
		var bi: Dictionary = bullets[order[i]]
		if not bi["alive"]:
			continue
		for j in range(i + 1, order.size()):
			var bj: Dictionary = bullets[order[j]]
			if not bj["alive"]:
				continue
			if bi["owner_kind"] == bj["owner_kind"]:
				continue
			if Aabb.overlaps(bi["x"], bi["y"], Bullet.HALF_W, Bullet.HALF_H,
					bj["x"], bj["y"], Bullet.HALF_W, Bullet.HALF_H):
				bi["alive"] = false
				bj["alive"] = false
				changed = true
				break
	# (6) bullet-vs-tank.
	var hx_t: int = (config.tank_w_tiles * config.tile_size_sub) / 2
	var hy_t: int = (config.tank_h_tiles * config.tile_size_sub) / 2
	for idx2 in order:
		var b2: Dictionary = bullets[idx2]
		if not b2["alive"]:
			continue
		if b2["owner_kind"] == "enemy":
			for pidx in range(_player_count):
				var pt: Dictionary = players[pidx]
				if not pt["alive"]:
					continue
				if Aabb.overlaps(b2["x"], b2["y"], Bullet.HALF_W, Bullet.HALF_H,
						pt["x"], pt["y"], hx_t, hy_t):
					# Helmet absorbs damage (acceptance #12c). Bullet is
					# consumed either way.
					b2["alive"] = false
					if t_ms >= int(pt["helmet_until_ms"]):
						# Damage path: kill the player and schedule a respawn
						# if lives remain. Acceptance #15b/c: game over only
						# when ALL players have lives==0 (and respawn timer
						# isn't pending) — see is_game_over().
						pt["alive"] = false
						lives_arr[pidx] = maxi(0, lives_arr[pidx] - 1)
						if lives_arr[pidx] > 0:
							pt["respawn_at_ms"] = t_ms + config.player_respawn_ms
					changed = true
					break
		else:  # player bullet
			for eidx in range(enemies.size()):
				var et: Dictionary = enemies[eidx]
				if not et["alive"]:
					continue
				if Aabb.overlaps(b2["x"], b2["y"], Bullet.HALF_W, Bullet.HALF_H,
						et["x"], et["y"], hx_t, hy_t):
					# Damage. Armor needs hp_for_kind hits; others die instantly.
					et["hp"] = int(et["hp"]) - 1
					if int(et["hp"]) <= 0:
						et["alive"] = false
						scores[int(b2["owner_idx"])] += config.score_for_kind(String(et["kind"]))
						wave_state["killed_count"] = int(wave_state.get("killed_count", 0)) + 1
						# Bonus enemies drop a power-up (acceptance #11).
						if bool(et.get("bonus", false)):
							Powerup.spawn_for_bonus_kill(self, _drop_rng, t_ms)
					b2["alive"] = false
					changed = true
					break
	# (5) bullet-vs-tile. Brick erosion uses bullet TRAVEL direction.
	# Steel only breaks for star ≥ 2. Either way, bullet is consumed on
	# contact with brick or steel.
	for idx3 in order:
		var b3: Dictionary = bullets[idx3]
		if not b3["alive"]:
			continue
		var hit_tile: bool = false
		for tr in Bullet.tiles_under_bullet(b3["x"], b3["y"], config):
			var c: int = tr[0]
			var r: int = tr[1]
			var tile: int = grid.get_tile(c, r)
			if tile == TileGrid.TILE_BRICK and grid.get_brick(c, r) != TileGrid.BRICK_DESTROYED:
				grid.erode_brick(c, r, b3["dir"])
				hit_tile = true
				break
			if tile == TileGrid.TILE_STEEL:
				if int(b3["star"]) >= 2:
					grid.break_steel(c, r)
				hit_tile = true
				break
		if hit_tile:
			b3["alive"] = false
			changed = true
	# (6) bullet-vs-base. Any bullet that overlaps the base tile destroys
	# both. Lose-condition wiring lands in the win/lose commit.
	if base_pos.size() == 2:
		var bx: int = (int(base_pos[0])) * config.tile_size_sub + config.tile_size_sub / 2
		var by: int = (int(base_pos[1])) * config.tile_size_sub + config.tile_size_sub / 2
		var bhx: int = config.tile_size_sub / 2
		var bhy: int = config.tile_size_sub / 2
		for idx4 in order:
			var b4: Dictionary = bullets[idx4]
			if not b4["alive"]:
				continue
			if grid.get_tile(int(base_pos[0]), int(base_pos[1])) != TileGrid.TILE_BASE:
				break  # already destroyed
			if Aabb.overlaps(b4["x"], b4["y"], Bullet.HALF_W, Bullet.HALF_H,
					bx, by, bhx, bhy):
				grid.set_tile(int(base_pos[0]), int(base_pos[1]), TileGrid.TILE_EMPTY)
				b4["alive"] = false
				changed = true
				break
	# (7) prune.
	var kept: Array = []
	for b5 in bullets:
		if b5["alive"]:
			kept.append(b5)
	if kept.size() != bullets.size():
		bullets = kept
		changed = true
	return changed


## Indices into `bullets[]` ordered by (owner_kind=player_first, owner_idx,
## bullet_idx). Used to give the within-sub-step resolution a deterministic
## tie-break that snapshot replays can reproduce.
func _bullet_iteration_order() -> Array:
	var players_part: Array = []
	var enemies_part: Array = []
	for i in range(bullets.size()):
		if bullets[i]["owner_kind"] == "player":
			players_part.append(i)
		else:
			enemies_part.append(i)
	players_part.sort_custom(func(a: int, b: int) -> bool:
		var ai: int = int(bullets[a]["owner_idx"])
		var bi: int = int(bullets[b]["owner_idx"])
		if ai != bi:
			return ai < bi
		return a < b)
	enemies_part.sort_custom(func(a: int, b: int) -> bool:
		var ai: int = int(bullets[a]["owner_idx"])
		var bi: int = int(bullets[b]["owner_idx"])
		if ai != bi:
			return ai < bi
		return a < b)
	return players_part + enemies_part


func _rng_state_snapshot() -> Dictionary:
	return {
		"spawn": _spawn_rng.state,
		"ai_target": _ai_target_rng.state,
		"ai_fire": _ai_fire_rng.state,
		"drop": _drop_rng.state,
		"pick": _pick_rng.state,
	}


static func _restore_rng(master_seed: int, tag: int, recorded_state: int) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = SubRng.make(master_seed, tag)
	r.state = recorded_state
	return r
