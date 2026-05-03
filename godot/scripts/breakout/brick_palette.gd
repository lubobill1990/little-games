extends RefCounted
## Brick color palette for breakout. color_id is set per-cell in the level
## resource; the scene resolves it to a Color via `for_color_id`.
##
## Indestructible bricks (passed via `destructible=false`) render in a flat
## gray that's clearly distinct from any normal palette entry, regardless of
## their color_id. This keeps level files terse: a level can stamp them all
## with color_id=0 and trust the renderer to surface their special role.

const _COLORS: Array[Color] = [
	Color(0.86, 0.30, 0.30),   # 0 — red
	Color(0.95, 0.70, 0.25),   # 1 — orange
	Color(0.96, 0.90, 0.36),   # 2 — yellow
	Color(0.45, 0.78, 0.40),   # 3 — green
	Color(0.40, 0.65, 0.92),   # 4 — blue
	Color(0.66, 0.46, 0.86),   # 5 — purple
]

const _INDESTRUCTIBLE: Color = Color(0.45, 0.45, 0.48)

const BG: Color = Color(0.07, 0.07, 0.10)
const PADDLE: Color = Color(0.92, 0.92, 0.95)
const BALL: Color = Color(0.98, 0.98, 0.98)
const HUD_TEXT: Color = Color(0.92, 0.92, 0.95)
const LETTERBOX: Color = Color.BLACK

static func for_color_id(color_id: int, destructible: bool = true) -> Color:
	if not destructible:
		return _INDESTRUCTIBLE
	if color_id < 0 or color_id >= _COLORS.size():
		return _COLORS[0]
	return _COLORS[color_id]
