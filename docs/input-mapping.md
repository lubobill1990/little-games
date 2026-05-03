# Input mapping

The `InputManager` autoload (added in task #2) exposes **semantic actions** so game code is the same on every platform.

## Default action set

| Action       | Keyboard       | Xbox / generic gamepad | DualSense / DS4    | Touch (mobile) |
|--------------|----------------|------------------------|--------------------|----------------|
| `move_left`  | ← / A          | D-pad ← / Left stick ← | D-pad ← / LSx ←    | Swipe / on-screen ← |
| `move_right` | → / D          | D-pad → / Left stick → | D-pad → / LSx →    | Swipe / on-screen → |
| `move_up`    | ↑ / W          | D-pad ↑                | D-pad ↑            | Swipe ↑ |
| `move_down`  | ↓ / S          | D-pad ↓                | D-pad ↓            | Swipe ↓ |
| `soft_drop`  | ↓ / S          | D-pad ↓                | D-pad ↓            | Hold-down zone |
| `hard_drop`  | Space          | A                      | Cross              | Tap-up zone    |
| `rotate_cw`  | ↑ / X          | B                      | Circle             | Right-half tap |
| `rotate_ccw` | Z              | X                      | Square             | Left-half tap  |
| `hold`       | C / Shift      | Y / LB                 | Triangle / L1      | Two-finger tap |
| `undo`       | Z              | Y                      | Triangle           | (HUD button)   |
| `pause`      | Esc / P        | Start / Menu           | Options            | Pause button   |

`move_up` and `move_down` are semantic 4-direction equivalents of `move_left`/`move_right` for grid-based games (Snake, 2048). They intentionally share keys with `rotate_cw` (↑) and `soft_drop` (↓); per-game scenes consume only the actions they care about, so the overlap is harmless.

`undo` shares its keyboard default (Z) with `rotate_ccw` and its gamepad default (Y / Triangle) with `hold`. Same rationale: 2048 listens for `undo`, Tetris listens for `rotate_ccw` / `hold` — actions don't compete unless a single scene subscribes to both, which none do.

## DAS / ARR (auto repeat)

Standard Tetris feel:

| Param | Default | Range  |
|-------|---------|--------|
| DAS (Delayed Auto Shift) | 167 ms (~10 frames @ 60Hz) | 50–500 ms |
| ARR (Auto Repeat Rate)   | 33 ms  (~2 frames)         | 0–200 ms  |

Settings screen (task #5) lets the user tune both, plus rebind every action.

## Gamepad detection

`Input.joy_connection_changed` drives a `connected` / `disconnected` signal on `InputManager`. UI surfaces the active controller name. Multiple controllers are supported but only player 1 is wired into game scenes (no local multiplayer in v1).

## Web specifics

Browsers expose gamepads via the [Gamepad API](https://developer.mozilla.org/en-US/docs/Web/API/Gamepad_API). Godot's web export consumes this transparently — the action map above just works. Caveats:

- The first gamepad input must come **after** the user has clicked the canvas (Chrome user-activation requirement).
- Safari iOS supports MFi controllers via the same API since iOS 13.
