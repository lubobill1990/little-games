extends RefCounted
## tank_level.gd — pure parsers for level tile maps and enemy rosters.
##
## File-IO is the SCENE's job (per CLAUDE.md "core has no OS calls"). This
## module exposes static parsers that take String content and return either
## a parsed structure or null + push_error on the first validation failure.
##
## Tile chars (per PRD §Terrain):
##   .  empty             (passable: tank+bullet)
##   B  brick             (blocks tank+bullet; bullet erodes half-brick)
##   S  steel             (blocks tank+bullet; star≥2 bullet destroys; else consumed)
##   W  water             (blocks tank w/o ship, passes bullets)
##   G  grass             (passable; visually covers tanks at scene level)
##   I  ice               (passable; tank slides 1 extra tile after release)
##   H  base / eagle      (any bullet hit → game over)
##   P  player spawn      (marker; topmost-leftmost = P1, next = P2)
##   E  enemy spawn       (marker)
##
## Roster lines: one of "basic|fast|power|armor", optional " +bonus" suffix.
## Whitespace-trimmed; blank lines and `#` comments ignored. CRLF tolerated.
## Per FC default, exactly 3 bonus markers per roster (enemies #4, #11, #18)
## but designers may move them — the validator only checks the count.

const Self := preload("res://scripts/tank/core/tank_level.gd")

const VALID_TILES: Array = [
	".", "B", "S", "W", "G", "I", "H", "P", "E"
]
const VALID_KINDS: Array = [
	"basic", "fast", "power", "armor"
]

const REQUIRED_BONUS_MARKERS: int = 3
const REQUIRED_ROSTER_LEN: int = 20  # FC standard: 20 enemies per level


## Parse both the tile-map text AND the roster text in one call.
## `player_count` ∈ {1, 2}. Returns:
##   { "tiles": [13 strings of 13 chars],
##     "roster": [{kind: String, bonus: bool}, …  20 entries],
##     "p1": [col, row], "p2": [col, row] | null }
## or null + push_error on the first validation failure.
static func parse_level(tiles_text: String, roster_text: String, player_count: int) -> Variant:
	var tiles: Variant = parse_tiles(tiles_text, player_count)
	if tiles == null:
		return null
	var roster: Variant = parse_roster(roster_text)
	if roster == null:
		return null
	# Find player spawn markers (topmost-leftmost = P1, next = P2).
	var spawns: Array = _find_player_spawns(tiles)
	# Player-count vs spawn-count cross-check (parse_tiles already enforced
	# count match, but locate them now for caller convenience).
	var p1: Array = spawns[0] if spawns.size() >= 1 else []
	var p2: Variant = spawns[1] if spawns.size() >= 2 else null
	return {
		"tiles": tiles,
		"roster": roster,
		"p1": p1,
		"p2": p2,
	}


## Parse JUST the tile map. Returns 13-string array (each 13 chars) on
## success, or null + push_error on validation failure.
static func parse_tiles(tiles_text: String, player_count: int) -> Variant:
	if player_count != 1 and player_count != 2:
		push_error("tank_level: player_count must be 1 or 2 (got %d)" % player_count)
		return null
	# CRLF-tolerant split, drop the trailing empty-string if the file ended
	# with a newline.
	var raw: PackedStringArray = tiles_text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var rows: PackedStringArray = PackedStringArray()
	for line in raw:
		# Right-trim trailing whitespace only — leading whitespace inside a
		# tile row is meaningful (would not match VALID_TILES).
		var t: String = line
		while t.length() > 0 and (t[t.length() - 1] == " " or t[t.length() - 1] == "\t"):
			t = t.substr(0, t.length() - 1)
		if t.length() == 0:
			continue
		rows.append(t)
	if rows.size() != 13:
		push_error("tank_level: tile map must have 13 non-empty rows (got %d)" % rows.size())
		return null
	var p_count: int = 0
	var e_count: int = 0
	var h_count: int = 0
	for r in range(13):
		var row: String = rows[r]
		if row.length() != 13:
			push_error("tank_level: row %d must be 13 chars wide (got %d)" % [r, row.length()])
			return null
		for c in range(13):
			var ch: String = row[c]
			if not VALID_TILES.has(ch):
				push_error("tank_level: row %d col %d has unknown tile char '%s'" % [r, c, ch])
				return null
			if ch == "P":
				p_count += 1
			elif ch == "E":
				e_count += 1
			elif ch == "H":
				h_count += 1
	if h_count < 1:
		push_error("tank_level: must contain at least one 'H' (base/eagle)")
		return null
	if e_count < 1:
		push_error("tank_level: must contain at least one 'E' (enemy spawn)")
		return null
	if p_count != player_count:
		push_error("tank_level: 'P' count %d does not match player_count %d" % [p_count, player_count])
		return null
	return rows


## Parse roster text into [{kind: String, bonus: bool}, …]. Returns null
## + push_error on validation failure. Blank lines and `#` comments are
## ignored. Whitespace-trimmed.
static func parse_roster(roster_text: String) -> Variant:
	var raw: PackedStringArray = roster_text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var out: Array = []
	for line in raw:
		var t: String = line.strip_edges()
		if t.is_empty():
			continue
		if t.begins_with("#"):
			continue
		# Tokenize on whitespace; first token = kind, optional " +bonus".
		var parts: PackedStringArray = t.split(" ", false)
		if parts.size() == 0:
			continue
		var kind: String = parts[0]
		if not VALID_KINDS.has(kind):
			push_error("tank_level: roster line '%s' has unknown kind '%s'" % [t, kind])
			return null
		var bonus: bool = false
		for i in range(1, parts.size()):
			var tag: String = parts[i].strip_edges()
			if tag == "+bonus":
				bonus = true
			elif tag.is_empty():
				continue
			else:
				push_error("tank_level: roster line '%s' has unknown tag '%s'" % [t, tag])
				return null
		out.append({"kind": kind, "bonus": bonus})
	if out.size() != REQUIRED_ROSTER_LEN:
		push_error("tank_level: roster must be exactly %d entries (got %d)" % [REQUIRED_ROSTER_LEN, out.size()])
		return null
	var bonus_count: int = 0
	for entry in out:
		if entry["bonus"]:
			bonus_count += 1
	if bonus_count != REQUIRED_BONUS_MARKERS:
		push_error("tank_level: roster must have exactly %d '+bonus' markers (got %d)" % [REQUIRED_BONUS_MARKERS, bonus_count])
		return null
	return out


## Returns enemy-spawn slots in declaration order (top-to-bottom,
## left-to-right). Each entry is [col, row]. Used by spawn.gd to pick
## "first free E slot".
static func find_enemy_spawns(tiles: PackedStringArray) -> Array:
	var out: Array = []
	for r in range(tiles.size()):
		var row: String = tiles[r]
		for c in range(row.length()):
			if row[c] == "E":
				out.append([c, r])
	return out


## Returns base (eagle) tile coords. There must be at least 1 by validator;
## if multiple, returns the topmost-leftmost (canonical for FC).
static func find_base(tiles: PackedStringArray) -> Array:
	for r in range(tiles.size()):
		var row: String = tiles[r]
		for c in range(row.length()):
			if row[c] == "H":
				return [c, r]
	return []


# --- internal ---

static func _find_player_spawns(tiles: PackedStringArray) -> Array:
	var out: Array = []
	for r in range(tiles.size()):
		var row: String = tiles[r]
		for c in range(row.length()):
			if row[c] == "P":
				out.append([c, r])
	return out
