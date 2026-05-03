# Persistence

The contract for *user-visible* persistence (settings, high scores, per-game state) across all games in this repo. Everything written to `user://` flows through `Settings.set_value` / `get_value` (defined in #5a). This file documents the **key namespace** and the **schema-mismatch policy**.

> **Out of scope:** non-game persistence (window size, telemetry, achievements). Add a section here if/when those land.

## Key namespace

Keys are dotted paths. Per-game keys are prefixed with the game's `id` (also used by `GameInfo` and the menu): `tetris`, `snake`, `g2048`, `breakout`. Cross-game settings have no prefix.

`level_NN` is **two-digit zero-padded** (`level_01` … `level_99`). New games append rows to the table; **every polish PR for a new game must update this file**.

| Key | Type | Owner | Notes |
|---|---|---|---|
| `audio.master`           | `float` 0..1   | #5a                | master volume |
| `audio.sfx`              | `float` 0..1   | #5a                | SFX bus volume |
| `audio.music`            | `float` 0..1   | #5a                | music bus volume |
| `input.das_ms`           | `int`          | #5a                | Delayed-Auto-Shift, ms |
| `input.arr_ms`           | `int`          | #5a                | Auto-Repeat-Rate, ms |
| `input.binding.<action>.<slot>` | `Dictionary` | #5b          | rebind slot — `<slot> ∈ {kbd, pad}` |
| `tetris.best`            | `int`          | #5a                | replaces `tetris.high_score` |
| `snake.best.<difficulty>` | `int`         | snake-polish (#19) | `<difficulty> ∈ {easy, normal, hard}` |
| `g2048.best`             | `int`          | 2048-polish (#21)  | 4×4 only in v1 |
| `breakout.best.level_NN` | `int`          | breakout-polish (#23) | per-level high score |
| `breakout.best.run`      | `int`          | breakout-polish (#23) | best score across the full level pack |

Game IDs are intentionally **not** the project name (`2048` would lead with a digit and is awkward to use as a key prefix); the canonical id is `g2048`.

## Snapshot schema

Every per-game `core/`'s `snapshot()` returns a Godot `Dictionary` with at least:

- `version: int` — schema version. Bumped on **breaking** changes (renamed/removed fields, changed semantics). Adding a new optional field that the scene tolerates is *not* breaking.
- … game-specific fields (board, pieces, score, etc.).

This is the canonical wire format between core ↔ scene ↔ persistence:

- The **scene** consumes `snapshot()` to render. It diffs successive snapshots between ticks to detect what changed (see `docs/architecture.md` § "Snapshot diffs, not signals").
- **Persistence** writes a snapshot subset (typically `version` + a high-score field) under the namespaced key.

Cores **never** emit Godot signals. They are pure GDScript with no `Node` dependency — see `CLAUDE.md` § "Code style".

## Schema-mismatch policy

When loading a stored value (high score or saved game) whose embedded `version` is **older than the current code's version** AND no migration is registered for that step:

1. **Wipe** the offending key (treat as if absent).
2. **Toast** the user once: *"Saved data was from an older version and has been reset."*
3. Continue from the default value (e.g. `0` for `*.best`).

This is consistent with the #5b decision: prefer brutal correctness over silent data corruption. Migrations are only written for transitions where carrying old data forward has user value (e.g. a high score). The toast is shown at most once per session.

A `version` **newer** than the code's current version is the same situation in reverse — happens when a user downgrades. Same handling: wipe + toast.

## Adding a new persistence key — checklist

When a new game's polish PR lands, or when a cross-game setting is added:

1. Append the row to the table above (key, type, owner, notes).
2. If the key holds a structured value (not a primitive), bump the schema version and document the new field shape in the relevant `core/`.
3. Reference this file from the issue's PRD so reviewers can confirm the namespace is honored.
