extends Object
## Palette + draw constants for the Invaders scene. No Image/ImageTexture —
## all visuals are `_draw` calls keyed off these constants.

# Background, bunker, player, bullets, UFO, HUD text.
const BG: Color = Color(0.02, 0.02, 0.05, 1.0)
const PLAYER: Color = Color(0.30, 0.95, 0.40)         # classic green
const PLAYER_BULLET: Color = Color(1.00, 1.00, 1.00)
const BUNKER: Color = Color(0.30, 0.95, 0.40)
const UFO: Color = Color(0.95, 0.30, 0.40)            # red saucer
const HUD_TEXT: Color = Color(1.00, 1.00, 1.00)
const SCORE_POPUP: Color = Color(1.00, 0.85, 0.20)
const EXPLOSION: Color = Color(1.00, 0.65, 0.10)

# Per-row colors for the formation. Indexed by row (0 = top).
# Five-row default formation: top is purple, mid bands cyan, bottom-most yellow.
const ROW_COLORS: Array[Color] = [
	Color(0.85, 0.40, 0.95),    # row 0 (octopus / 30 pts)
	Color(0.30, 0.85, 0.95),    # row 1 (crab / 20 pts)
	Color(0.30, 0.85, 0.95),    # row 2 (crab / 20 pts)
	Color(0.95, 0.95, 0.30),    # row 3 (squid / 10 pts)
	Color(0.95, 0.95, 0.30),    # row 4 (squid / 10 pts)
]

# Three-color palette for enemy bullets, picked by index for visual variety.
const ENEMY_BULLET_COLORS: Array[Color] = [
	Color(1.00, 1.00, 1.00),
	Color(1.00, 0.85, 0.20),
	Color(0.85, 0.40, 0.95),
]

# March-pose toggle. The formation_layer flips between these two on every
# formation step; each pose is a distinct hand-coded glyph in `_draw`.
const MARCH_POSE_A: int = 0
const MARCH_POSE_B: int = 1


static func row_color(row_idx: int) -> Color:
	if row_idx < 0 or row_idx >= ROW_COLORS.size():
		return Color(0.6, 0.6, 0.6, 1.0)
	return ROW_COLORS[row_idx]


static func enemy_bullet_color(bullet_idx: int) -> Color:
	if bullet_idx < 0:
		return ENEMY_BULLET_COLORS[0]
	return ENEMY_BULLET_COLORS[bullet_idx % ENEMY_BULLET_COLORS.size()]
