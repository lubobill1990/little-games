extends Resource
## Breakout level — brick layout as a pure data record.
##
## Bricks are laid out on a regular grid; per-cell metadata lives in
## `cells` (parallel to row*cols index). An empty cell has hp == 0.
## The state expands this into a flat list of brick AABBs at create() time.

@export var rows: int = 6
@export var cols: int = 10
@export var brick_w: float = 28.0
@export var brick_h: float = 10.0
@export var origin_x: float = 20.0           # left edge of first column
@export var origin_y: float = 20.0           # top edge of first row

# `cells.size() == rows * cols`. Each cell is { hp: int, value: int,
# destructible: bool, color_id: int }. hp == 0 means "no brick here".
@export var cells: Array = []
