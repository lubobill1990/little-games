# Adding a new game

A walkthrough that should let you ship a new classic in a single PR.

> The framework that makes this slick lands in task #6. Until then, follow the
> structure below by hand and the menu integration will be a one-liner once #6
> ships.

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
│   ├── <game>.tscn            # Root scene, implements the Game contract
│   └── <game>.gd
└── tests/unit/<game>/
    └── test_*.gd
```

## 3. Implement the `Game` scene contract

(API stabilises in task #6.)

```gdscript
extends Control
class_name Game

signal score_reported(value: int)
signal exited

func start(seed: int = 0) -> void: ...
func pause() -> void: ...
func resume() -> void: ...
func teardown() -> void: ...
```

## 4. Register in the menu

Add the game to `globals/game_registry.gd` (task #6):

```gdscript
const GAMES := [
	{ "id": "tetris", "title": "Tetris", "scene": "res://scenes/tetris/tetris.tscn" },
	{ "id": "snake",  "title": "Snake",  "scene": "res://scenes/snake/snake.tscn"  },  # ← new
]
```

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
