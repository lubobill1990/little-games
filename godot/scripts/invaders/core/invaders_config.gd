extends Resource
## Invaders configuration. Pure value object — no Node, no signals.
## Validated at create() time; tunneling-cap constraint is hard-asserted.
##
## All units: float pixels, int milliseconds. World origin top-left, +Y down.

# --- World ---
@export var world_w: float = 224.0
@export var world_h: float = 256.0

# --- Formation grid ---
@export var rows: int = 5
@export var cols: int = 11
@export var cell_w: float = 16.0          # horizontal stride between cells
@export var cell_h: float = 14.0          # vertical stride between rows
@export var enemy_hx: float = 6.0         # half-extent x of an enemy AABB
@export var enemy_hy: float = 5.0         # half-extent y of an enemy AABB

# Formation origin (top-left of the grid) at wave 1.
@export var formation_start_x: float = 16.0
@export var formation_start_y: float = 40.0

# Step cadence: every step_ms_init at full population, accelerating to
# min_step_ms when only one enemy remains.
@export var step_ms_init: int = 800
@export var min_step_ms: int = 80
@export var step_dx: float = 8.0          # horizontal shift per step
@export var step_dy: float = 8.0          # vertical drop on edge bounce

# --- Player ---
@export var player_w: float = 16.0
@export var player_h: float = 8.0
@export var player_y: float = 232.0       # center y; top edge at player_y - h/2
@export var player_max_speed_px_s: float = 90.0
@export var lives_start: int = 3
@export var invuln_ms: int = 1500

# --- Bullets ---
@export var player_bullet_w: float = 2.0
@export var player_bullet_h: float = 6.0
@export var player_bullet_speed: float = 220.0  # px/sec, upward
@export var enemy_bullet_w: float = 2.0
@export var enemy_bullet_h: float = 6.0
@export var enemy_bullet_speed: float = 90.0    # px/sec, downward

# Per-tick (fixed 16 ms sub-step) probability that an enemy bullet spawns.
@export var enemy_fire_p_init: float = 0.012
# Cap on simultaneous enemy bullets at wave 1.
@export var enemy_bullets_max_init: int = 3
# Cap goes up by +1 every N waves.
@export var enemy_bullets_per_wave: int = 1
@export var enemy_bullets_wave_step: int = 1

# --- Bunkers ---
@export var bunker_count: int = 4
@export var bunker_cell_w: float = 2.0
@export var bunker_cell_h: float = 2.0
@export var bunker_y: float = 188.0       # center y of bunker rect

# --- UFO ---
@export var ufo_w: float = 16.0
@export var ufo_h: float = 7.0
@export var ufo_y: float = 32.0           # center y
@export var ufo_speed: float = 60.0
@export var ufo_interval_ms_init: int = 25000
@export var ufo_jitter_ms: int = 5000     # ± half on each side

# --- Wave progression ---
# Each wave: formation_start_y -= wave_drop_y (clamped >= wave_min_start_y).
@export var wave_drop_y: float = 8.0
@export var wave_min_start_y: float = 24.0
# step_ms_init shrinks by this factor each wave (multiplicative; clamped).
@export var wave_speed_factor: float = 0.92

# --- Time ---
# Internal fixed sub-step (60 Hz physics).
@export var sub_step_ms: int = 16
@export var max_sub_steps_per_tick: int = 8
