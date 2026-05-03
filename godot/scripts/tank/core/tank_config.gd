extends Resource
## Tank configuration. Pure value object — no Node, no signals.
## Validated by TankGameState.create() at game-start time;
## tunneling-cap constraint is hard-asserted there.
##
## Units: integer sub-pixels, integer milliseconds. World origin top-left,
## +Y down. 1 tile = 16 sub-px on each axis; world is 13×13 tiles =
## 208×208 sub-px. Tanks are 2×2 tiles (32×32 sub-px AABB).

# --- World (locked: every level is 13×13) ---
@export var world_w_tiles: int = 13
@export var world_h_tiles: int = 13
@export var tile_size_sub: int = 16            # sub-px per tile, per axis

# --- Tanks ---
@export var tank_w_tiles: int = 2              # 2×2 tile AABB
@export var tank_h_tiles: int = 2
# Rail-snap: when intent direction flips perpendicular, snap to nearest
# 4-sub-px boundary. FC PPU quarter-tile alignment — without this, tanks
# can't enter 2-wide corridors.
@export var rail_snap_sub: int = 4
# Movement speeds (sub-px per sub-step).
@export var tank_speed_basic_sub: int = 1
@export var tank_speed_fast_sub: int = 2
@export var tank_speed_player_sub: int = 1
# Per-kind enemy HP. armor=4 hits, others=1.
@export var enemy_hp_basic: int = 1
@export var enemy_hp_fast: int = 1
@export var enemy_hp_power: int = 1
@export var enemy_hp_armor: int = 4

# --- Bullets ---
# Speeds: normal for star-≤0 / basic enemies, fast for star-≥1 / power enemies.
@export var bullet_speed_normal_sub: int = 4   # sub-px per sub-step
@export var bullet_speed_fast_sub: int = 6
# Tunneling cap reference: bullet_speed_max * sub_step_dt < min(half-brick height,
# tank height in sub-px). With normal=4, fast=6, half-brick=8, this passes.

# --- Cooldowns ---
@export var fire_cooldown_ms: int = 200

# --- AI ---
@export var ai_recheck_ms: int = 800
@export var ai_p_target_base: float = 0.15
@export var ai_p_fire: float = 0.05            # rolled per sub-step per enemy

# --- Spawning ---
@export var wave_size: int = 20                # FC standard
@export var max_alive_enemies: int = 4         # FC standard
@export var spawn_interval_ms: int = 2000      # ms between spawn attempts
@export var spawn_blink_ms: int = 1000         # blink time before materialize

# --- Player ---
@export var player_lives_start: int = 3
@export var player_respawn_ms: int = 2000
@export var player_helmet_on_respawn_ms: int = 3000

# --- Power-up durations (refresh-on-pickup, no stacking) ---
@export var helmet_pickup_ms: int = 10000
@export var freeze_pickup_ms: int = 5000
@export var shovel_pickup_ms: int = 20000

# --- Star upgrade thresholds ---
# 0=normal, 1=fast bullet, 2=can break steel, 3=2 bullets at once.
@export var star_max: int = 3
@export var star_max_bullets_l3: int = 2

# --- Score ---
@export var score_basic: int = 100
@export var score_fast: int = 200
@export var score_power: int = 300
@export var score_armor: int = 400

# --- Time ---
@export var sub_step_ms: int = 16              # 62.5 Hz
@export var max_sub_steps_per_tick: int = 8


## True iff the bullet-speed × sub-step-dt fits inside the smallest
## destructible half-brick height (or tank height) in sub-px. Caller is
## TankGameState.create(); on false → push_error and return null.
func tunneling_ok() -> bool:
	# Half-brick is half a tile = tile_size_sub / 2 = 8 sub-px.
	var half_brick_h: int = tile_size_sub / 2
	var tank_h: int = tank_h_tiles * tile_size_sub
	var min_target: int = mini(half_brick_h, tank_h)
	# Bullets advance bullet_speed_*_sub per sub-step (sub_step_ms).
	# Constraint: max bullet step < min_target so it can't tunnel through.
	var max_step: int = maxi(bullet_speed_normal_sub, bullet_speed_fast_sub)
	return max_step < min_target


## Score value for a given enemy kind. Used by TankGameState on kill.
func score_for_kind(kind: String) -> int:
	match kind:
		"basic": return score_basic
		"fast": return score_fast
		"power": return score_power
		"armor": return score_armor
		_: return 0


## HP for a given enemy kind.
func hp_for_kind(kind: String) -> int:
	match kind:
		"basic": return enemy_hp_basic
		"fast": return enemy_hp_fast
		"power": return enemy_hp_power
		"armor": return enemy_hp_armor
		_: return 1
