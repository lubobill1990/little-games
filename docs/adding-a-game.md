# Adding a new game

A walkthrough that should let you ship a new classic in a single PR.

## 1. Open a tracking issue

Use the `Task` template. Fill in PRD, deliverables, acceptance, tests. Move the
card on the [Project board](https://github.com/users/lubobill1990/projects/5/views/1)
to **Ready** when the PRD is approved.

## 2. Lay out files

```
godot/
├── scripts/<game>/
│   ├── core/                  # PURE logic — no Node, no `_process`, no OS calls.
│   │   ├── state.gd
│   │   └── ...
│   └── controller.gd          # Glues core to the scene
├── scenes/<game>/
│   ├── <game>.tscn            # Root scene, implements the GameHost contract
│   └── <game>.gd
└── tests/unit/<game>/
    └── test_*.gd
```

## 3. Implement the GameHost contract

The menu launches a game by instancing its root scene and calling lifecycle
methods on the root node. The contract is **duck-typed** — any node that
implements these methods and emits `exit_requested` qualifies, regardless of
whether it extends `Control`, `Node2D`, or `Node`.

```gdscript
extends Control  # or Node2D / Node — whatever the game needs

signal exit_requested()              # game wants to return to menu
signal score_reported(value: int)    # optional but recommended; menu may show

func start(seed: int = 0) -> void:   # called by host after instancing
	pass
func pause() -> void:                # host requests pause (e.g. menu opened)
	pass
func resume() -> void:               # host releases pause
	pass
func teardown() -> void:             # host is about to free us; drop refs
	pass
```

The game emits `exit_requested` from its pause overlay's "Back to menu" button
and from the Game-Over overlay's "Menu" button. The host listens, calls
`teardown()`, frees the instance, and refocuses the menu.

When the scene is loaded **directly** (e.g. as the project's `main_scene` for
local testing), it should auto-call `start(_fresh_seed())` from `_ready` if
`get_tree().current_scene == self`. This keeps direct-launch and integration
tests working without a host wrapper.

## 4. Register in `GameRegistry`

`godot/scripts/core/game/game_registry.gd`:

```gdscript
const _GAMES: Array = [
	[&"tetris",     "Tetris",      "res://scenes/tetris/tetris.tscn",            ""],
	[&"snake_stub", "Snake (WIP)", "res://scenes/games/snake_stub/snake_stub.tscn", ""],
	[&"<your_id>",  "<Your Title>", "res://scenes/games/<your_dir>/<your_root>.tscn", "<icon_path or empty>"],
]
```

Scene paths are strings; the menu loads them lazily via `load()` on selection,
so unused games pay zero memory cost. `GameRegistry.validate()` runs at menu
boot — duplicate ids and missing scene paths surface in the menu's "Registry
problems" label and the offending entries are skipped.

## 5. Tests

- **Unit** — every rule of the game.
- **Scene** — input → core → render. Use `Input.parse_input_event`.
- **Integration** — at least one deterministic-seed end-to-end run.

CI must be green. PR cannot merge otherwise.

## 6. Manual smoke test matrix

| Platform | Mandatory? | Notes |
|---|---|---|
| Desktop, keyboard | yes | |
| Desktop, gamepad | yes | At least one Xbox-layout pad |
| Web | yes | Chrome + Firefox |
| Android APK | yes | Pixel-class device or emulator |
| iOS | optional | Skip until task #7 ships iOS export |
