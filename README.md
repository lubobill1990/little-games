# little-games

A growing collection of classic games, built with **Godot 4** to play on **web, Android, iOS, and desktop** — with first-class **gamepad** support.

> **Status**: bootstrap. First game in flight: **Tetris**.

## Live demo

▶︎ **<https://lubobill1990.github.io/little-games/>** — auto-deployed from `main` after every push.

> First load is ~10 MB (Godot Web runtime + game). Click the canvas after the
> "Press to play" prompt — browsers require a user gesture before audio/input
> can start. Web export ships with threading off, so it works on plain GitHub
> Pages without COOP/COEP headers.

## How to play

1. Open the demo URL above.
2. Use **arrows / D-pad** to navigate the menu, **Enter / A** to confirm.
3. In Tetris: **arrows** to move, **↑ / X** to rotate, **Space / A** to hard-drop, **C / Y** to hold, **Esc / Start** to pause.

Native binaries (Windows zip, eventually Android APK) ship as attachments on tagged releases at <https://github.com/lubobill1990/little-games/releases>.

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
