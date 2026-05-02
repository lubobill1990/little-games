# little-games

A growing collection of classic games, built with **Godot 4** to play on **web, Android, iOS, and desktop** — with first-class **gamepad** support.

> **Status**: bootstrap. First game in flight: **Tetris**.

## Live demo

GitHub Pages deploy lands with task #7. Until then, run locally.

## Run locally

Install Godot 4.6 standard (`scoop install godot` on Windows), then:

```bash
godot --path godot
```

Or open `godot/project.godot` in the editor and press F5.

## Run tests

```bash
godot --headless --path godot -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

## Controls (target)

| Action     | Keyboard       | Gamepad                  |
|------------|----------------|--------------------------|
| Move       | ← →            | D-pad / Left stick       |
| Soft drop  | ↓              | D-pad down               |
| Hard drop  | Space          | A / Cross                |
| Rotate CW  | ↑ / X          | B / Circle               |
| Rotate CCW | Z              | X / Square               |
| Hold       | C / Shift      | Y / Triangle / LB        |
| Pause      | Esc            | Start / Options          |

Final mapping is implemented in task #2 and made user-rebindable in task #5.

## How this repo is built

- Every change is tracked as a [GitHub issue](https://github.com/lubobill1990/little-games/issues) on the [Project board](https://github.com/users/lubobill1990/projects/5/views/1).
- Tasks are linear: one issue → one PR → merge → next.
- Three test layers: unit, scene, integration. CI runs them all.

See [`CLAUDE.md`](./CLAUDE.md) for the full contributor guide and [`docs/`](./docs) for architecture & input mapping.

## License

MIT — see `LICENSE` (added with the first release tag).
