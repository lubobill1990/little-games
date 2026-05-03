extends RefCounted
## InvadersGameState — pure formation/bullet/bunker/UFO rules. No Node,
## no signals. Architecture rule: tick() returns bool indicating change;
## scene-side observes via snapshot diff (no signals from core).
##
## Snapshot version 1 (see snapshot_schema in Dev plan):
##   - `divers: []` and `rng_dive` are reserved for the Galaga-style dive
##     follow-up PR. v1 code never reads or writes them past initialization.
##   - Three sub-RNGs (`_bullet_rng`, `_ufo_rng`, `_dive_rng`) are derived
##     from master `seed` at create() with disjoint XOR tags. Adding a
##     consumer in a later PR (e.g. dive) cannot perturb v1 fixtures.
##
## Coordinates: world origin top-left, +Y down. Player is at the bottom.

const Self := preload("res://scripts/invaders/core/invaders_state.gd")
const InvadersConfig := preload("res://scripts/invaders/core/invaders_config.gd")
const InvadersLevel := preload("res://scripts/invaders/core/invaders_level.gd")
const Aabb := preload("res://scripts/invaders/core/aabb.gd")
const Formation := preload("res://scripts/invaders/core/formation.gd")
const BunkerGrid := preload("res://scripts/invaders/core/bunker_grid.gd")
const BunkerErosion := preload("res://scripts/invaders/core/bunker_erosion.gd")
const Ufo := preload("res://scripts/invaders/core/ufo.gd")

const SCHEMA_VERSION: int = 1

# Sub-RNG XOR tags. Bumping these is a BREAKING change to v1 goldens.
# Chosen as visually-distinct hex constants; values themselves are arbitrary.
const _RNG_TAG_BULLET: int = 0xB011E7   # "BULLET"-shaped
const _RNG_TAG_UFO: int = 0x0FF0EF      # "OFFOEF"
const _RNG_TAG_DIVE: int = 0xD17EFE     # "DIVE"-shaped


# --- Config / level ---
var config: InvadersConfig
var level: InvadersLevel

# --- Formation state ---
var live_mask: PackedByteArray   # length rows*cols; 1 = alive
var enemy_kinds: PackedByteArray # length rows*cols; per-cell kind id
var formation_ox: float = 0.0
var formation_oy: float = 0.0
var formation_dir: int = 1       # +1 right, -1 left
var formation_step_ms: int = 0
var formation_last_step_ms: int = 0

# --- Player ---
var player_x: float = 0.0
var player_intent_vx: float = 0.0
var player_alive: bool = true
var lives: int = 0
var invuln_until_ms: int = 0

# --- Bullets ---
# Player has at most one alive at a time.
var player_bullet_alive: bool = false
var player_bullet_x: float = 0.0
var player_bullet_y: float = 0.0
# Enemy bullets: array of {x,y}.
var enemy_bullets: Array = []

# --- Bunkers ---
# bunkers[i] is a BunkerGrid; their world top-left positions are derived
# from config (evenly spaced). Stored alongside for snapshot fidelity.
var bunkers: Array = []
var bunker_origins: Array = []   # Array[Vector2]; aligned with `bunkers`.

# --- Wave / score ---
var wave: int = 1
var score: int = 0

# --- UFO ---
var ufo_alive: bool = false
var ufo_x: float = 0.0
var ufo_dir: int = 1
var ufo_spawn_ms: int = 0
var last_ufo_spawn_ms: int = 0

# --- Reserved for invaders-dive ---
var divers: Array = []   # Always [] in v1; dive PR populates without bumping version.

# --- Time ---
var last_tick_ms: int = 0
var initialized_clock: bool = false
var sub_step_accum_ms: int = 0
# Accumulator for formation cadence; refilled each sub-step by dt_ms.
var formation_step_ms_accum: int = 0

# --- RNGs ---
var _master_seed: int = 0
var _bullet_rng: RandomNumberGenerator
var _ufo_rng: RandomNumberGenerator
var _dive_rng: RandomNumberGenerator   # reserved; not consumed in v1


# ---------------- Construction ----------------

static func create(game_seed: int, cfg: InvadersConfig, lvl: InvadersLevel) -> Self:
	# Tunneling cap (acceptance #12): the fastest moving thing per sub-step
	# must travel less than the smallest collidable feature.
	var sub_dt_s: float = float(cfg.sub_step_ms) / 1000.0
	var max_speed: float = maxf(cfg.player_bullet_speed, cfg.enemy_bullet_speed)
	var step_dist: float = max_speed * sub_dt_s
	var min_feature: float = minf(2.0 * cfg.enemy_hy,
			minf(cfg.cell_h,
			minf(cfg.player_h,
			minf(cfg.bunker_cell_h,
			cfg.player_bullet_h))))
	if step_dist >= min_feature:
		push_error("InvadersGameState.create: tunneling cap violated — max bullet step %f >= min feature %f. Reduce bullet speeds or sub_step_ms." \
				% [step_dist, min_feature])
		return null

	var s: Self = Self.new()
	s.config = cfg
	s.level = lvl
	s._master_seed = game_seed
	s._bullet_rng = _make_rng(game_seed, _RNG_TAG_BULLET)
	s._ufo_rng = _make_rng(game_seed, _RNG_TAG_UFO)
	s._dive_rng = _make_rng(game_seed, _RNG_TAG_DIVE)

	# Formation: all alive, kinds set per-row.
	var n: int = cfg.rows * cfg.cols
	s.live_mask = PackedByteArray()
	s.live_mask.resize(n)
	s.enemy_kinds = PackedByteArray()
	s.enemy_kinds.resize(n)
	for r in range(cfg.rows):
		var kind: int = lvl.row_kinds[r] if r < lvl.row_kinds.size() else 0
		for c in range(cfg.cols):
			s.live_mask[r * cfg.cols + c] = 1
			s.enemy_kinds[r * cfg.cols + c] = kind
	s.formation_ox = cfg.formation_start_x
	s.formation_oy = cfg.formation_start_y
	s.formation_dir = 1
	s.formation_step_ms = cfg.step_ms_init
	s.formation_last_step_ms = 0

	# Player.
	s.player_x = cfg.world_w * 0.5
	s.lives = cfg.lives_start
	s.player_alive = true
	s.invuln_until_ms = 0

	# Bunkers: equally spaced across the world width.
	s.bunkers = []
	s.bunker_origins = []
	var bunker_world_w: float = lvl.bunker_w_cells * cfg.bunker_cell_w
	var bunker_world_h: float = lvl.bunker_h_cells * cfg.bunker_cell_h
	# Total free space = world_w - count * bunker_world_w; gaps are evenly
	# distributed (count+1 gaps, including the two outer margins).
	var total_w: float = cfg.bunker_count * bunker_world_w
	var gap: float = (cfg.world_w - total_w) / float(cfg.bunker_count + 1)
	for i in range(cfg.bunker_count):
		var ox: float = gap + i * (bunker_world_w + gap)
		var oy: float = cfg.bunker_y - bunker_world_h * 0.5
		s.bunkers.append(BunkerGrid.create(lvl.bunker_w_cells, lvl.bunker_h_cells, lvl.bunker_pattern))
		s.bunker_origins.append(Vector2(ox, oy))

	s.score = 0
	s.wave = 1
	return s


static func _make_rng(seed_int: int, tag: int) -> RandomNumberGenerator:
	# Derive a sub-RNG by XOR-tagging the master seed. Each consumer is
	# isolated: adding a new sub-RNG cannot perturb existing streams.
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = seed_int ^ tag
	return r


# ---------------- Public API ----------------

func set_player_intent(velocity_x: float) -> void:
	player_intent_vx = clampf(velocity_x, -config.player_max_speed_px_s, config.player_max_speed_px_s)


func fire() -> bool:
	if not player_alive:
		return false
	if player_bullet_alive:
		return false
	# Spawn at player's top-center.
	player_bullet_alive = true
	player_bullet_x = player_x
	player_bullet_y = config.player_y - config.player_h * 0.5 - config.player_bullet_h * 0.5
	return true


func is_game_over() -> bool:
	return lives <= 0 or _formation_reached_player()


func current_wave() -> int:
	return wave


func set_last_tick(now_ms: int) -> void:
	# Shift internal clock without simulating. Resets the formation step
	# accumulator so a long pause doesn't burst-step on resume.
	last_tick_ms = now_ms
	initialized_clock = true
	# Re-anchor formation pacing to "now".
	formation_last_step_ms = now_ms


func tick(now_ms: int) -> bool:
	if is_game_over():
		# Even when game-over we still want to honour set_last_tick semantics,
		# but no simulation runs.
		last_tick_ms = now_ms
		initialized_clock = true
		return false
	if not initialized_clock:
		last_tick_ms = now_ms
		initialized_clock = true
		formation_last_step_ms = now_ms
	var elapsed: int = now_ms - last_tick_ms
	if elapsed <= 0:
		return false
	var changed: bool = false
	var sub: int = config.sub_step_ms
	var cap: int = config.max_sub_steps_per_tick
	sub_step_accum_ms += elapsed
	last_tick_ms = now_ms
	var iters: int = 0
	while sub_step_accum_ms >= sub and iters < cap:
		if _sub_step(sub, now_ms - sub_step_accum_ms + sub):
			changed = true
		sub_step_accum_ms -= sub
		iters += 1
		if is_game_over():
			break
	# Drain leftover (drop frames) to avoid unbounded backlog.
	if sub_step_accum_ms >= sub:
		sub_step_accum_ms = sub_step_accum_ms % sub
	return changed


# ---------------- Internal: sub-step ----------------

func _sub_step(dt_ms: int, _at_ms: int) -> bool:
	var dt_s: float = float(dt_ms) / 1000.0
	var changed: bool = false

	# 1. Player horizontal motion.
	var new_px: float = player_x + player_intent_vx * dt_s
	# Clamp to world (player half-width on each side).
	var phw: float = config.player_w * 0.5
	new_px = clampf(new_px, phw, config.world_w - phw)
	if not is_equal_approx(new_px, player_x):
		player_x = new_px
		changed = true

	# 2. Player bullet motion + collisions.
	if player_bullet_alive:
		player_bullet_y -= config.player_bullet_speed * dt_s
		if player_bullet_y < 0.0:
			player_bullet_alive = false
			changed = true
		else:
			# Check vs enemies.
			if _player_bullet_vs_enemies():
				changed = true
			elif _player_bullet_vs_ufo():
				changed = true
			elif _player_bullet_vs_bunkers():
				changed = true
		if player_bullet_alive:
			changed = true   # moved

	# 3. Enemy bullets motion + collisions.
	if not enemy_bullets.is_empty():
		var i: int = 0
		while i < enemy_bullets.size():
			var b: Dictionary = enemy_bullets[i]
			var ny: float = float(b["y"]) + config.enemy_bullet_speed * dt_s
			if ny > config.world_h:
				enemy_bullets.remove_at(i)
				changed = true
				continue
			b["y"] = ny
			enemy_bullets[i] = b
			# vs bunkers.
			if _enemy_bullet_vs_bunkers(i):
				changed = true
				continue   # bullet consumed; index now points to next
			# vs player.
			if _enemy_bullet_vs_player(i):
				changed = true
				continue
			i += 1
			changed = true   # moved

	# 4. Formation step (cadence based on accumulated time).
	#    We bill the sub-step's dt against the formation's step_ms accumulator.
	formation_step_ms_accum += dt_ms
	if formation_step_ms_accum >= formation_step_ms:
		formation_step_ms_accum -= formation_step_ms
		_step_formation()
		# Recompute step_ms after possible enemy deaths since last step.
		var live: int = Formation.live_count(live_mask)
		formation_step_ms = Formation.step_ms_for_population(live, config.rows * config.cols,
				config.step_ms_init, config.min_step_ms)
		changed = true

	# 5. Enemy fire chance.
	if enemy_bullets.size() < _max_enemy_bullets() \
			and _bullet_rng.randf() < config.enemy_fire_p_init:
		if _spawn_enemy_bullet():
			changed = true

	# 6. UFO lifecycle.
	if _step_ufo(dt_s, dt_ms):
		changed = true

	# 7. Invulnerability tick.
	if invuln_until_ms > 0:
		invuln_until_ms = maxi(0, invuln_until_ms - dt_ms)

	# 8. Wave clear?
	if Formation.live_count(live_mask) == 0:
		_advance_wave()
		changed = true

	return changed


# ---------------- Internal: formation ----------------

func _step_formation() -> void:
	# Tentatively shift origin horizontally; check edge bounce.
	var tentative_ox: float = formation_ox + formation_dir * config.step_dx
	var bx_after: Vector2 = Formation.bounds_x(live_mask, config.rows, config.cols,
			tentative_ox, formation_oy, config.cell_w, config.cell_h, config.enemy_hx)
	if bx_after.x == -INF:
		return  # no live enemies (shouldn't happen here)
	if bx_after.x < 0.0 or bx_after.y > config.world_w:
		# Edge bounce: reverse + drop. Do NOT also apply the horizontal
		# step on the bounce frame (matches arcade behaviour).
		formation_dir = -formation_dir
		formation_oy += config.step_dy
	else:
		formation_ox = tentative_ox


# ---------------- Internal: bullets ----------------

func _player_bullet_vs_enemies() -> bool:
	# Iterate cells; first hit wins. Bullet is consumed.
	for r in range(config.rows):
		for c in range(config.cols):
			if live_mask[r * config.cols + c] != 1:
				continue
			var ecx: float = formation_ox + c * config.cell_w + config.cell_w * 0.5
			var ecy: float = formation_oy + r * config.cell_h + config.cell_h * 0.5
			if Aabb.overlaps(player_bullet_x, player_bullet_y,
					config.player_bullet_w * 0.5, config.player_bullet_h * 0.5,
					ecx, ecy, config.enemy_hx, config.enemy_hy):
				live_mask[r * config.cols + c] = 0
				var kind_idx: int = enemy_kinds[r * config.cols + c]
				var val: int = level.row_values[kind_idx] if kind_idx < level.row_values.size() else 10
				score += val
				player_bullet_alive = false
				return true
	return false


func _player_bullet_vs_ufo() -> bool:
	if not ufo_alive:
		return false
	if Aabb.overlaps(player_bullet_x, player_bullet_y,
			config.player_bullet_w * 0.5, config.player_bullet_h * 0.5,
			ufo_x, config.ufo_y, config.ufo_w * 0.5, config.ufo_h * 0.5):
		score += Ufo.pick_score(_ufo_rng)
		ufo_alive = false
		player_bullet_alive = false
		return true
	return false


func _player_bullet_vs_bunkers() -> bool:
	for i in range(bunkers.size()):
		var bg: BunkerGrid = bunkers[i]
		var origin: Vector2 = bunker_origins[i]
		var hit: Dictionary = {}
		if bg.aabb_hit(origin.x, origin.y, config.bunker_cell_w, config.bunker_cell_h,
				player_bullet_x, player_bullet_y,
				config.player_bullet_w * 0.5, config.player_bullet_h * 0.5, hit):
			bg.apply_stamp(BunkerErosion.player_up_stamp(),
					BunkerErosion.PLAYER_UP_W, BunkerErosion.PLAYER_UP_H,
					int(hit["cx"]), int(hit["cy"]),
					BunkerErosion.PLAYER_UP_ANCHOR_SX, BunkerErosion.PLAYER_UP_ANCHOR_SY)
			player_bullet_alive = false
			return true
	return false


func _enemy_bullet_vs_bunkers(idx: int) -> bool:
	var b: Dictionary = enemy_bullets[idx]
	for i in range(bunkers.size()):
		var bg: BunkerGrid = bunkers[i]
		var origin: Vector2 = bunker_origins[i]
		var hit: Dictionary = {}
		if bg.aabb_hit(origin.x, origin.y, config.bunker_cell_w, config.bunker_cell_h,
				float(b["x"]), float(b["y"]),
				config.enemy_bullet_w * 0.5, config.enemy_bullet_h * 0.5, hit):
			bg.apply_stamp(BunkerErosion.enemy_down_stamp(),
					BunkerErosion.ENEMY_DOWN_W, BunkerErosion.ENEMY_DOWN_H,
					int(hit["cx"]), int(hit["cy"]),
					BunkerErosion.ENEMY_DOWN_ANCHOR_SX, BunkerErosion.ENEMY_DOWN_ANCHOR_SY)
			enemy_bullets.remove_at(idx)
			return true
	return false


func _enemy_bullet_vs_player(idx: int) -> bool:
	if not player_alive or invuln_until_ms > 0:
		return false
	var b: Dictionary = enemy_bullets[idx]
	if Aabb.overlaps(float(b["x"]), float(b["y"]),
			config.enemy_bullet_w * 0.5, config.enemy_bullet_h * 0.5,
			player_x, config.player_y,
			config.player_w * 0.5, config.player_h * 0.5):
		enemy_bullets.remove_at(idx)
		_player_hit()
		return true
	return false


func _player_hit() -> void:
	lives -= 1
	if lives <= 0:
		player_alive = false
		return
	# Brief invulnerability + clear all enemy bullets currently on screen.
	invuln_until_ms = config.invuln_ms
	enemy_bullets.clear()
	player_bullet_alive = false


# ---------------- Internal: enemy bullets ----------------

func _max_enemy_bullets() -> int:
	# +1 every `wave_step` waves above wave 1.
	var bonus: int = ((wave - 1) / config.enemy_bullets_wave_step) * config.enemy_bullets_per_wave
	return config.enemy_bullets_max_init + bonus


func _spawn_enemy_bullet() -> bool:
	var seed_col: int = _bullet_rng.randi()
	var col: int = Formation.find_firing_column(live_mask, config.rows, config.cols, seed_col)
	if col < 0:
		return false
	var row: int = Formation.bottom_row(live_mask, config.rows, config.cols, col)
	if row < 0:
		return false
	var ecx: float = formation_ox + col * config.cell_w + config.cell_w * 0.5
	var ecy: float = formation_oy + row * config.cell_h + config.cell_h * 0.5
	# Spawn just below the bottom of the firing enemy.
	var bx: float = ecx
	var by: float = ecy + config.enemy_hy + config.enemy_bullet_h * 0.5 + 0.001
	enemy_bullets.append({"x": bx, "y": by})
	return true


# ---------------- Internal: UFO ----------------

func _step_ufo(dt_s: float, dt_ms: int) -> bool:
	var changed: bool = false
	if ufo_alive:
		ufo_x += ufo_dir * config.ufo_speed * dt_s
		# Off-screen?
		var hw: float = config.ufo_w * 0.5
		if (ufo_dir > 0 and ufo_x - hw > config.world_w) \
				or (ufo_dir < 0 and ufo_x + hw < 0.0):
			ufo_alive = false
			last_ufo_spawn_ms = last_tick_ms
		changed = true
	else:
		# Note: should_spawn uses the master "now" (last_tick_ms is fine).
		if Ufo.should_spawn(_ufo_rng, last_tick_ms, last_ufo_spawn_ms,
				config.ufo_interval_ms_init, config.ufo_jitter_ms):
			ufo_alive = true
			ufo_dir = Ufo.pick_direction(_ufo_rng)
			ufo_spawn_ms = last_tick_ms
			ufo_x = -config.ufo_w * 0.5 if ufo_dir > 0 else config.world_w + config.ufo_w * 0.5
			changed = true
	return changed


# ---------------- Internal: wave / loss ----------------

func _formation_reached_player() -> bool:
	var by: Vector2 = Formation.bounds_y(live_mask, config.rows, config.cols,
			formation_ox, formation_oy, config.cell_w, config.cell_h, config.enemy_hy)
	if by.x == -INF:
		return false
	# Player's top edge is player_y - h/2; if any enemy AABB-bottom >= it, loss.
	var player_top: float = config.player_y - config.player_h * 0.5
	return by.y >= player_top


func _advance_wave() -> void:
	wave += 1
	# Reset formation: all alive, higher start, faster.
	var n: int = config.rows * config.cols
	live_mask = PackedByteArray()
	live_mask.resize(n)
	for r in range(config.rows):
		var kind: int = level.row_kinds[r] if r < level.row_kinds.size() else 0
		for c in range(config.cols):
			live_mask[r * config.cols + c] = 1
			enemy_kinds[r * config.cols + c] = kind
	# New start_y = clamp(start_y - drop, min, start_y).
	var ny: float = maxf(config.wave_min_start_y,
			config.formation_start_y - (wave - 1) * config.wave_drop_y)
	formation_oy = ny
	formation_ox = config.formation_start_x
	formation_dir = 1
	# Speed: shrink step_ms_init by factor each wave.
	var ms: float = float(config.step_ms_init) * pow(config.wave_speed_factor, wave - 1)
	formation_step_ms = maxi(config.min_step_ms, int(round(ms)))
	formation_step_ms_accum = 0
	# Active UFO is force-removed at wave change (acceptance #10).
	ufo_alive = false
	# Bullets are kept; gameplay-wise it's fine and avoids surprising the player.


# ---------------- Snapshot / restore ----------------

func snapshot() -> Dictionary:
	# Deep copy of mutable arrays so caller can't mutate our state.
	var lm: PackedByteArray = PackedByteArray()
	lm.resize(live_mask.size())
	for i in range(live_mask.size()):
		lm[i] = live_mask[i]
	var ek: PackedByteArray = PackedByteArray()
	ek.resize(enemy_kinds.size())
	for i in range(enemy_kinds.size()):
		ek[i] = enemy_kinds[i]
	var ebs: Array = []
	for b in enemy_bullets:
		ebs.append({"x": float(b["x"]), "y": float(b["y"])})
	var bgs: Array = []
	for bg in bunkers:
		bgs.append(bg.snapshot_cells())
	var ufo_obj: Variant = null
	if ufo_alive:
		ufo_obj = {"x": ufo_x, "dir": ufo_dir, "spawn_ms": ufo_spawn_ms}
	return {
		"version": SCHEMA_VERSION,
		"wave": wave,
		"score": score,
		"lives": lives,
		"formation": {
			"ox": formation_ox,
			"oy": formation_oy,
			"dir": formation_dir,
			"step_ms": formation_step_ms,
			"last_step_ms": formation_last_step_ms,
		},
		"enemies": lm,
		"enemy_kinds": ek,
		"player": {
			"x": player_x,
			"alive": player_alive,
			"invuln_until_ms": invuln_until_ms,
		},
		"player_bullet": {
			"x": player_bullet_x,
			"y": player_bullet_y,
			"alive": player_bullet_alive,
		},
		"enemy_bullets": ebs,
		"bunkers": bgs,
		"ufo": ufo_obj,
		"last_ufo_spawn_ms": last_ufo_spawn_ms,
		"divers": [],
		"rng_master": _master_seed,
		"rng_bullet": int(_bullet_rng.state),
		"rng_ufo": int(_ufo_rng.state),
		"rng_dive": int(_dive_rng.state),
	}


static func from_snapshot(snap: Dictionary, cfg: InvadersConfig, lvl: InvadersLevel) -> Self:
	var s: Self = create(int(snap.get("rng_master", 0)), cfg, lvl)
	if s == null:
		return null
	s.wave = int(snap["wave"])
	s.score = int(snap["score"])
	s.lives = int(snap["lives"])
	var f: Dictionary = snap["formation"]
	s.formation_ox = float(f["ox"])
	s.formation_oy = float(f["oy"])
	s.formation_dir = int(f["dir"])
	s.formation_step_ms = int(f["step_ms"])
	s.formation_last_step_ms = int(f["last_step_ms"])
	# Restore mutable buffers.
	var lm: PackedByteArray = snap["enemies"]
	s.live_mask = PackedByteArray()
	s.live_mask.resize(lm.size())
	for i in range(lm.size()):
		s.live_mask[i] = lm[i]
	var ek: PackedByteArray = snap["enemy_kinds"]
	s.enemy_kinds = PackedByteArray()
	s.enemy_kinds.resize(ek.size())
	for i in range(ek.size()):
		s.enemy_kinds[i] = ek[i]
	var p: Dictionary = snap["player"]
	s.player_x = float(p["x"])
	s.player_alive = bool(p["alive"])
	s.invuln_until_ms = int(p["invuln_until_ms"])
	var pb: Dictionary = snap["player_bullet"]
	s.player_bullet_x = float(pb["x"])
	s.player_bullet_y = float(pb["y"])
	s.player_bullet_alive = bool(pb["alive"])
	s.enemy_bullets = []
	for b in snap["enemy_bullets"]:
		s.enemy_bullets.append({"x": float(b["x"]), "y": float(b["y"])})
	# Bunkers. Re-derive bunker_origins via create() — they are deterministic
	# from cfg + count, and the create() call above already set them.
	var bgs: Array = snap["bunkers"]
	s.bunkers = []
	for i in range(bgs.size()):
		s.bunkers.append(BunkerGrid.from_snapshot(lvl.bunker_w_cells, lvl.bunker_h_cells, bgs[i]))
	# UFO.
	if snap["ufo"] == null:
		s.ufo_alive = false
	else:
		var u: Dictionary = snap["ufo"]
		s.ufo_alive = true
		s.ufo_x = float(u["x"])
		s.ufo_dir = int(u["dir"])
		s.ufo_spawn_ms = int(u["spawn_ms"])
	s.last_ufo_spawn_ms = int(snap["last_ufo_spawn_ms"])
	s.divers = []  # reserved; v1 always []
	# RNG states. We use master_seed in create() to set initial states; now
	# overwrite with the saved states so randomness picks up from the exact
	# point of the snapshot.
	s._bullet_rng.state = int(snap.get("rng_bullet", s._bullet_rng.state))
	s._ufo_rng.state = int(snap.get("rng_ufo", s._ufo_rng.state))
	s._dive_rng.state = int(snap.get("rng_dive", s._dive_rng.state))
	return s
