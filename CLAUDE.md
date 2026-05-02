# CLAUDE.md

This file is the entry point for any Claude Code session working on this repo. **Read it fully before doing anything.**

---

## 1. Project mission

Build a small, growing collection of **classic games** that play well on **web, Android, iOS, and desktop**, with **first-class gamepad support**. First game shipped: **Tetris**. The repo is meant to be the canonical, transparent log of how the games are built — every change goes through a tracked issue and PR.

## 2. Tech stack

- **Engine**: [Godot 4.6](https://godotengine.org/) (GDScript). Standard build, **not** the .NET build.
- **Test framework**: [GUT](https://github.com/bitwes/Gut) (vendored under `godot/addons/gut/`)
- **CI**: GitHub Actions, headless Godot, `gut_cmdln.gd`
- **Deploy targets** (in priority order):
  1. **Web** → GitHub Pages (`https://lubobill1990.github.io/little-games/`)
  2. **Android** → debug APK as Actions artifact
  3. **Windows** → zipped exe per release
  4. **iOS** → deferred (needs Apple developer account)

### Why Godot, not Flutter

Flutter Web has a heavy CanvasKit payload and laggy input; Flutter has no first-class gamepad API and would need three platform shims to behave consistently. Godot solves both natively, exports the same project to every target we care about, and `Input.is_action_pressed` works identically on every platform. See `docs/architecture.md` for the full rationale.

## 3. Repository layout

```
little-games/
├── CLAUDE.md                  # ← you are here
├── README.md                  # user-facing intro + demo link
├── godot/                     # Godot project root (open this in the editor)
│   ├── project.godot
│   ├── globals/               # Autoloads (singletons): InputManager, GameState
│   ├── scenes/
│   │   ├── menu/              # Game selection menu
│   │   └── tetris/            # Tetris scenes
│   ├── scripts/
│   │   ├── core/              # Cross-game shared utilities
│   │   └── tetris/            # Tetris-specific GDScript classes (pure logic in tetris/core/)
│   ├── assets/                # Art, audio, fonts
│   ├── addons/
│   │   └── gut/               # Vendored GUT
│   └── tests/
│       ├── unit/              # Pure-logic GUT tests
│       └── integration/       # Scene-driven end-to-end tests
├── docs/
│   ├── architecture.md
│   ├── input-mapping.md
│   └── adding-a-game.md
└── .github/
    ├── workflows/
    │   ├── ci.yml             # Run GUT on every push/PR
    │   └── deploy-web.yml     # Export web build and publish to gh-pages
    ├── ISSUE_TEMPLATE/
    └── pull_request_template.md
```

## 4. How to work in this repo

### Local prerequisites

- Godot 4.6 standard (Windows: `scoop install godot`; macOS: `brew install --cask godot`; Linux: official binary)
- Optional: Web/Android export templates installed from the editor (`Editor → Manage Export Templates`)

### Run the game

```bash
godot --path godot
```

Or open `godot/project.godot` in the Godot editor and press F5.

### Run tests

```bash
godot --headless --path godot -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Same command runs in CI. **All tests must be green before merging a PR.**

### Export builds

Templates required. From the editor: `Project → Export → Add… → <platform>`. Web export goes to `build/web/`.

## 5. Process — non-negotiable rules

### Issues + PRs

- **Every change has a GitHub issue first.** Issues are tracked at <https://github.com/lubobill1990/little-games/issues> and on Project board <https://github.com/users/lubobill1990/projects/5/views/1>.
- **Tasks are linear**, not parallel. Each task builds on the previous one. PR titles use the form `task/NN-<short-name>`. Example: `task/03-tetris-core`.
- **One issue = one PR.** Don't bundle. Don't fragment.
- PR body must reference the issue (`Closes #N`) and include a "How tested" section.
- A PR is mergeable only when: CI green, manual smoke test passed (or impossible), reviewer (or self-review with explicit notes) signed off.

### Task status workflow (Project board columns)

Each task card moves through five columns. **Move it manually at every step** — the columns are the single source of truth for "what's the state of this task right now".

| Column | Meaning | When to move in | When to move out |
|---|---|---|---|
| **Backlog** | Idea / placeholder. PRD not yet written. | Issue created. | PRD section in the issue is filled and approved. |
| **Ready** | Fully scoped, ready to be picked up. PRD + deliverables + acceptance + test plan all written. | PRD approved. | Implementation work begins. |
| **In progress** | Someone is actively working on it. A branch exists. | Branch checked out, work started. | All deliverables done, PR opened. |
| **In review** | PR is open and awaiting human review. CI green. | PR opened against main. | Reviewer approves and PR is merged. |
| **Done** | Merged into main. Acceptance criteria verified. | PR merged. | (Stays here.) |

Hard rules:
- Do **not** open a PR while the card is still in Ready or Backlog. Move it to **In progress** first.
- Do **not** mark a card **Done** until the PR is merged on `main` and CI on `main` is green.
- If review uncovers blocking issues, move the card back to **In progress** until ready for re-review.
- If a task is abandoned, close the issue and add a comment explaining why; don't leave it stuck mid-column.

### Commits

- Conventional-ish: `feat:`, `fix:`, `test:`, `chore:`, `docs:`, `refactor:`, `ci:`.
- Reference the issue in the body when relevant.

### Code style

- GDScript with **static typing** (`var x: int`, `func foo(b: Board) -> void`). The compiler will check it.
- Tabs for indentation (Godot default).
- Pure logic lives outside scenes (no `Node` references). This is what makes tests cheap.
- Never write Godot-specific calls (e.g. `print`, `OS.`, `_process`) inside `scripts/*/core/`.

### Tests

Three layers, all required:

1. **Unit tests** — pure logic (rotation, kicks, scoring, bag). `godot/tests/unit/`.
2. **Scene tests** — input → core → render wiring. Use `Input.parse_input_event` to simulate.
3. **Integration tests** — scripted gameplay sessions with deterministic seeds. `godot/tests/integration/`.

CI fails the PR if coverage of new core logic drops or any test fails.

## 6. Conventions for adding a new game

Once the multi-game framework lands, follow `docs/adding-a-game.md`. Short version:

1. Open a tracking issue and add it to the Project board.
2. Add `godot/scripts/<game>/core/` (pure logic) and `godot/scenes/<game>/` (Godot scene).
3. Implement the `Game` scene contract.
4. Register in the menu.
5. Tests in all three layers.

## 7. Things you (Claude) should not do

- Do **not** add Flutter, React Native, Unity, or any other engine. The decision is made.
- Do **not** introduce `.NET`/C# Godot — keep one runtime.
- Do **not** edit `project.godot` by hand if avoidable; open the editor.
- Do **not** commit binary export templates, build artifacts, or `.godot/` cache. These belong in `.gitignore`.
- Do **not** open a PR without a backing issue.
- Do **not** mark a task complete in the project board if any test is red.
