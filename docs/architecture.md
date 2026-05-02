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

## Directory map

See `CLAUDE.md` §3.

## Build & deploy targets

| Target | How | When |
|---|---|---|
| Web | `--export-release "Web"` → `gh-pages` | every push to main |
| Android APK | `--export-release "Android"` → Actions artifact | every push to main |
| Windows zip | `--export-release "Windows Desktop"` → release attachment | on `v*` tag |
| iOS | manual, Apple developer account required | deferred |
