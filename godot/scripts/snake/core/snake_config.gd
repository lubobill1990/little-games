extends Resource
## Snake game configuration. Pure value object — no Node, no OS, no signals.
## Drives SnakeGameState behavior; one SnakeConfig per session/difficulty.

@export var grid_w: int = 20
@export var grid_h: int = 20
@export var walls: bool = true              # true = head into edge → game over; false = wraps
@export var start_step_ms: int = 200        # initial ms per step
@export var min_step_ms: int = 60           # floor; level curve never goes below this
@export var level_every: int = 5            # foods per level-up
@export var level_factor: float = 0.85      # step_ms *= factor on level-up
@export var max_steps_per_tick: int = 5     # cap iterations per tick() — prevents stutter on long pauses
