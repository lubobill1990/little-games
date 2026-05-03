extends Resource
## Breakout configuration. Pure value object — no Node, no signals.
## Validated at create() time; tunneling-cap constraint is hard-asserted.

@export var world_w: float = 320.0
@export var world_h: float = 240.0

@export var paddle_w: float = 48.0
@export var paddle_h: float = 6.0
@export var paddle_y: float = 220.0           # top of paddle
@export var paddle_max_speed_px_s: float = 240.0

# Ball is treated internally as an AABB with half-extent = ball_radius.
@export var ball_radius: float = 3.0
@export var ball_speed_start: float = 120.0   # px/sec; magnitude of |velocity|

# Paddle x-bias parameter. Reflected vx = bias_t * ball_speed * MAX_X
# (bias_t in [-1,1]); vy = -sqrt(speed^2 - vx^2). Piecewise linear, no trig.
@export var bias_max_x: float = 0.95

@export var lives_start: int = 3

# Fixed-step integration. Sub-step duration in milliseconds.
@export var step_dt_ms: int = 10
# Cap on sub-steps per tick(now_ms) call. Bounds work on dropped frames.
@export var max_steps_per_tick: int = 8
