extends RefCounted
## Per-value color + font ramp for 2048 tiles. Pure value object — no Node,
## no Engine. Lookups by tile value; values above the table fall back to
## HIGH_TILE styling so the renderer never needs to special-case overflow.

# Background colors keyed to powers of two. Mirrors the classic Gabriele Cirulli
# palette but a touch more saturated to read on dark backgrounds.
const _BG: Dictionary = {
	2:    Color("#eee4da"),
	4:    Color("#ede0c8"),
	8:    Color("#f2b179"),
	16:   Color("#f59563"),
	32:   Color("#f67c5f"),
	64:   Color("#f65e3b"),
	128:  Color("#edcf72"),
	256:  Color("#edcc61"),
	512:  Color("#edc850"),
	1024: Color("#edc53f"),
	2048: Color("#edc22e"),
}
const _FG_DARK: Color = Color("#776e65")   # used for 2 / 4
const _FG_LIGHT: Color = Color("#f9f6f2")  # everything else
const _BG_HIGH: Color = Color("#3c3a32")   # > 2048 fallback
const _BG_EMPTY: Color = Color("#cdc1b4")  # background grid cell

const _BOARD_BG: Color = Color("#bbada0")  # whole-board background

static func bg_for(value: int) -> Color:
	if _BG.has(value):
		return _BG[value]
	return _BG_HIGH

static func fg_for(value: int) -> Color:
	if value <= 4:
		return _FG_DARK
	return _FG_LIGHT

static func empty_cell_color() -> Color:
	return _BG_EMPTY

static func board_bg_color() -> Color:
	return _BOARD_BG

# Font size shrinks for 4-digit and 5-digit numbers so the label fits.
static func font_size_for(value: int, cell_px: float) -> int:
	# Heuristic: fit roughly 3 wide-glyphs across the cell. Reserve ~70 % of
	# cell width for the text glyph block.
	var digits: int = max(1, str(value).length())
	var ratio: float = 0.55 if digits <= 2 else (0.45 if digits == 3 else (0.35 if digits == 4 else 0.28))
	return int(cell_px * ratio)
