extends Resource
## 2048 game configuration. Pure value object — no Node, no signals.
## Drives Game2048State behavior; one config per session/difficulty.

@export var size: int = 4                    # grid width = height
@export var target_value: int = 2048         # win threshold (cell value)
@export var four_probability: float = 0.1    # P(spawn=4); rest spawns 2
