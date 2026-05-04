# Tank — level + roster `.txt` format

Two text files describe one level. Both go through `TankLevel.parse()`
(in `godot/scripts/tank/core/tank_level.gd`); the host scene reads the
files and passes the contents — the parser does no file I/O. CRLF and LF
line endings are tolerated.

## Level file (`<name>.txt`) — 13×13 grid of tile chars

Exactly **13 rows of 13 characters**. One char per tile. Every char must
appear in the table below; anything else fails the loader with a
`push_error` and `parse()` returns `null`.

| Char | Tile         | Notes                                                        |
| :--: | ------------ | ------------------------------------------------------------ |
| `.`  | empty        | passable by tanks and bullets                                |
| `B`  | brick        | half-brick erosion; bullet from south clears bottom half     |
| `S`  | steel        | whole-tile; only star ≥ 2 bullets destroy it                 |
| `W`  | water        | bullets pass through; tank-no-ship blocked, tank-with-ship OK|
| `G`  | grass        | passable by everything; visually overlays tanks/bullets      |
| `I`  | ice          | passable; future "slip" semantics will live here             |
| `H`  | base         | exactly one per level — destroying it ends the game          |
| `P`  | player spawn | one per player slot (1 or 2 — must match `player_count`)     |
| `E`  | enemy spawn  | up to 4. Spawn slots are these tiles in row-major order.     |

Markers (`H`/`P`/`E`) are read from the grid then **replaced with
empty**: the tile underneath a marker is always passable empty space at
runtime. Spawn coordinates are remembered separately.

### Required marker counts

- `H` count == 1
- `P` count == `player_count` argument passed to `parse()` (1 or 2)
- `E` count >= 1, ≤ 4 (matches FC's 4 enemy spawn slots)

Wrong counts or wrong row/column count → `push_error` + `null`.

### Example (`tests/unit/tank/fixtures/level01.txt`)

```
.............
.....E.E.E...
.............
.BBB.SSSS....
.BBB.SSSS....
.BBB.SSSS....
.BBB.........
......WWW....
......WWW....
.....GGGGG...
.....GIIIG...
.....P.HP...E
.............
```

Two players (P1 left, P2 right of the base), one base (H, row 11), four
enemy spawn slots (E on row 1 plus an extra E on row 11).

## Roster file (`<name>.roster.txt`) — 20 lines, one enemy per line

Exactly **20 non-blank, non-comment lines**. Each line names one enemy
in spawn order:

```
<kind>[ +bonus]
```

- `<kind>` is one of `basic`, `fast`, `power`, `armor`.
- The optional ` +bonus` suffix marks an enemy whose death drops a
  power-up. **Exactly 3** `+bonus` markers per roster — the FC convention
  is enemies #4, #11, #18 (1-indexed), but any 3 are accepted.
- Lines starting with `#` are comments. Blank lines are ignored.
- Whitespace around the kind / suffix is trimmed.

Wrong roster length, wrong bonus count, or unknown kind → `push_error`
+ `null`.

### Example (`tests/unit/tank/fixtures/level01.roster.txt`)

```
# level01 roster — FC default: bonus markers at #4, #11, #18.
basic
basic
basic
basic +bonus
basic
basic
basic
basic
basic
basic
basic +bonus
basic
basic
basic
basic
basic
basic
basic +bonus
basic
basic
```

## Loading from a host scene

```gdscript
const TankLevel := preload("res://scripts/tank/core/tank_level.gd")
const TankState := preload("res://scripts/tank/core/tank_state.gd")
const TankConfig := preload("res://scripts/tank/core/tank_config.gd")

func _start(seed: int, player_count: int) -> TankState:
    var tiles: String = FileAccess.get_file_as_string("res://levels/level01.txt")
    var roster: String = FileAccess.get_file_as_string("res://levels/level01.roster.txt")
    var s: TankState = TankState.create(seed, tiles, roster, player_count, TankConfig.new())
    if s == null:
        push_error("level load failed — see prior push_error for the cause")
    return s
```

`TankState.create()` parses the level + roster, validates the
tunneling cap (`bullet_speed_max < min(half-brick height, tank height)`),
and seeds five sub-RNGs from the master `seed` via tag-XOR. Same seed +
same level + same input trace = byte-equal `snapshot()` (verified by
`tests/unit/tank/test_full_level_smoke.gd`).
