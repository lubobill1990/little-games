extends RefCounted
## Snake palette — single source of truth for grid/snake/food/HUD colors.
## Pure value object; no Node, no Engine. Future skinning attaches to this.

const BG: Color           = Color(0.07, 0.10, 0.07, 1.0)
const GRID_LINE: Color    = Color(0.13, 0.18, 0.13, 1.0)
const SNAKE_HEAD: Color   = Color(0.55, 0.95, 0.45, 1.0)
const SNAKE_BODY: Color   = Color(0.30, 0.70, 0.30, 1.0)
const FOOD: Color         = Color(0.95, 0.45, 0.45, 1.0)
const WALL: Color         = Color(0.40, 0.30, 0.20, 1.0)
const HUD_TEXT: Color     = Color(0.92, 0.92, 0.88, 1.0)
const OVERLAY_DIM: Color  = Color(0, 0, 0, 0.60)
