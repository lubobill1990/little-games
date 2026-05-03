# Architecture

## One sentence

A Godot 4 monorepo of self-contained classic games sharing a thin core (input, settings, persistence, menu) so each new game is "drop in a scene + register in the menu".

## Why Godot, not Flutter / Unity / web-only

| Concern | Flutter | Unity | Pure web | **Godot 4** |
|---|---|---|---|---|
| Web payload | 1.5–2.5 MB CanvasKit | 5–15 MB WASM | tiny | ~3–5 MB but loads progressively |
| Input latency on web | poor | OK | best | good |
| Gamepad on web/Android/iOS | three platform shims | OK | Gamepad API only on web | one API everywhere |
| Game loop / sprite renderer | bolted on (Flame) | yes | DIY | yes (native) |
| Open source / no royalty | yes | royalty above threshold | yes | yes (MIT) |
| Same codebase Web + Android + iOS + desktop | yes (with caveats) | yes | no native distribution | **yes** |

Godot wins on the pareto frontier for "small classic games on every platform with gamepads". See the [history of this decision](https://github.com/lubobill1990/little-games/issues/1) (the bootstrap PR).

## Layering

```
+--------------------------------------------------+
|  Per-game scene (e.g. scenes/tetris/)            |
|  - rendering, animation, level UI                |
+--------------------------------------------------+
|  Per-game core (scripts/<game>/core/)            |
|  - PURE GDScript logic. No Node references.      |
|  - 100% unit-testable.                           |
+--------------------------------------------------+
|  Shared cross-game services (globals/, scripts/core/) |
|  - InputManager: semantic actions across kbd/pad/touch|
|  - GameInfo: project metadata                    |
|  - Settings: persistence to user://              |
+--------------------------------------------------+
|  Godot 4 runtime                                 |
+--------------------------------------------------+
```

The hard rule: **per-game `core/` must not import `Node` or anything Godot-specific** (only `Resource`, primitives, math). This keeps the game rules independently testable and portable should we ever swap the rendering layer.

## Snapshot diffs, not signals

Per-game `core/` exposes its evolving state via `snapshot()` returning a `Dictionary` (new cores SHOULD include a `version: int` field — see `docs/persistence.md`). Scenes detect what changed by **diffing successive snapshots between ticks** rather than subscribing to per-state-bit signals. Reasons:

- Cores stay `Node`-free (the testability contract above).
- Replay/integration tests can drive a core deterministically and assert on snapshots without a render layer attached.
- One uniform mechanism replaces ad-hoc per-event callbacks.

**Exception — one-shot events.** Cores MAY expose Godot `signal`s for *discrete events* that aren't usefully captured by snapshot diffs (e.g. `piece_locked` carrying line-clear metadata, `game_over` carrying a reason code). These are fire-and-forget notifications, never used to communicate ongoing state. The tetris core (`scripts/tetris/core/game_state.gd`) uses both mechanisms: snapshot for the board/piece state, signals for `piece_locked` / `game_over`. The general rule: if the scene needs to *react* to a one-shot moment (SFX, screen-shake, modal), a signal is fine; if it needs to *render* a value, that value goes in the snapshot.

See `docs/persistence.md` for the canonical key namespace and schema-mismatch policy that builds on this contract.

## Directory map

See `CLAUDE.md` §3.

## Build & deploy targets

| Target | How | When |
|---|---|---|
| Web | `--export-release "Web"` → `gh-pages` | every push to main |
| Android APK | `--export-release "Android"` → Actions artifact | every push to main |
| Windows zip | `--export-release "Windows Desktop"` → release attachment | on `v*` tag |
| iOS | manual, Apple developer account required | deferred |
