# CLAUDE.md

Entry point for any Claude session in this repo. Read once, then act.

## Brevity contract

Every line in this file costs context for every future session. **If you (Claude) already understand a convention, don't expand on it; if you've seen a project pattern five times this session, don't restate it back.** Keep PR bodies, commit messages, and issue updates tight — say what changed, why it matters, and how it was tested. Cut everything else.

When updating this file: prefer fewer words, bullet points over prose, and a single canonical statement of each rule. Do not duplicate what's already in `docs/`.

## 1. Mission

A growing collection of **classic games** for **web / Android / iOS / desktop**, with **first-class gamepad support**. First game: **Tetris**.

## 2. Stack

- **Engine**: Godot 4.6 standard (GDScript). Not the .NET build.
- **Tests**: GUT, vendored at `godot/addons/gut/`.
- **CI**: GitHub Actions, headless Godot.
- **Deploy**: Web (gh-pages) → Android APK artifact → Windows zip → iOS (deferred).

Rationale for Godot over Flutter / Unity / web-only: see `docs/architecture.md`.

## 3. Layout

```
godot/                  Godot project root
  globals/              Autoloads (GameInfo, InputManager, …)
  scenes/{menu,<game>}/
  scripts/
    core/               Cross-game shared utilities
    <game>/core/        Per-game PURE logic (no Node, no OS calls) — unit-testable
  assets/               Art, audio, fonts
  addons/gut/           Vendored test framework
  tests/{unit,integration}/
docs/                   architecture, input-mapping, adding-a-game
.github/                workflows, issue & PR templates
scripts/board.sh        Move a Project board card by issue number
```

## 4. Run / test / export

```bash
godot --path godot                                                    # play
godot --headless --path godot -s addons/gut/gut_cmdln.gd \            # test
  -gconfig=res://.gutconfig.json
godot --headless --path godot --export-release "Web" build/web/index.html
```

CI must be green before merge. Same command runs there.

## 5. Process

### Issues + PRs

- Every change starts as a GitHub issue. Issues live on Project #5: <https://github.com/users/lubobill1990/projects/5/views/1>.
- Tasks are **linear**. One issue → one PR → merge → next.
- Branch name: `task/NN-<slug>`.
- PR body: link the issue (`Closes #N`) + "How tested" section.

### Task status workflow

```mermaid
flowchart LR
    Backlog["Backlog<br/>(idea)"]
    Ready["Ready<br/>(PRD + Dev plan written<br/>and unambiguous)"]
    InProgress["In progress<br/>(branch + impl)"]
    InReview["In review<br/>(PR open, CI green)"]
    ChangesRequested["Changes requested<br/>(reviewer asked for fixes,<br/>author iterating)"]
    Done["Done<br/>(merged on main)"]

    Backlog -->|Claude writes PRD + Dev plan;<br/>sub-agent review optional<br/>(use for complex/uncertain scope)| Ready
    Ready -->|Claude opens branch, codes| InProgress
    InProgress -->|Claude opens PR| InReview
    InReview -->|reviewer (human or skill) approves & merges| Done
    InReview -.->|review requests changes| ChangesRequested
    ChangesRequested -->|author pushes fix| InReview
```

| State | What it means |
|---|---|
| **Backlog** | Issue exists, no PRD/plan yet. |
| **Ready** | PRD + Dev plan written and unambiguous (an implementer can pick it up without asking the author). Sub-agent review is optional — use it when scope is complex or sequencing is non-obvious. |
| **In progress** | Branch exists, code being written. |
| **In review** | PR open, CI green, awaiting reviewer (human or `gh-pr-review` skill). |
| **Changes requested** | Reviewer requested changes; author is iterating on the same branch/PR. Goes back to **In review** on the next push. |
| **Done** | Merged on `main`, CI green on `main`. |

**Reviewers**: a human and the `gh-pr-review` skill have equal authority to approve and merge. The skill enforces its own gates (see `.claude/skills/gh-pr-review/SKILL.md` §4b); a human can override at any time.

**Implementers**: a human and the `implement-task` skill (runs as `weavejamtom`, claims one Ready task per `/loop` tick) have equal authority to take Ready tasks. See `.claude/skills/implement-task/SKILL.md`.

**Hard rules** (Claude must obey, automatically):

1. **Move the card immediately on every transition.** Use `scripts/board.sh <issue> <Backlog|Ready|InProgress|InReview|ChangesRequested|Done>`. Don't batch.
2. **Backlog → Ready requires a clear PRD + Dev plan in the issue body.** "Clear" = an implementer can start without asking the author. Sub-agent review (`Plan` or `general-purpose`) is optional — reach for it when scope is complex, sequencing is non-obvious, or you'd otherwise hand-wave edge cases.
3. **No PR while in Backlog or Ready.** Move to In progress first.
4. **Done = merged on `main` + CI green on `main`.** Not "approved", not "branch ready".
5. **Review requests changes → Changes requested.** Author iterates on the same PR; the next push moves the card back to In review (the implementer / pusher is responsible for that transition).
6. **Abandoned task → close issue with reason; don't strand the card.**

#### PRD vs. Dev plan

Both go in the issue body, in labeled sections.

- **PRD** — *what & why*. Problem, goal, scope, non-goals, acceptance criteria.
- **Dev plan** — *how*. Files to add/modify, public APIs, test strategy, risks, commit sequence inside the PR.

Sub-agent (when used): poke holes in scope, sequencing, missing edge cases, simpler alternatives.

### Commits

Conventional-ish: `feat: …`, `fix: …`, `test: …`, `chore: …`, `docs: …`, `refactor: …`, `ci: …`. Reference issue when relevant.

### Code style

- GDScript, **statically typed** (`var x: int`, `-> void`).
- Tabs (Godot default).
- Per-game `core/` must not import `Node` or call OS/Engine APIs. This is the testability contract.
- Per-game `core/` exposes evolving state via `snapshot() -> Dictionary`; scenes diff snapshots between ticks. Signals reserved for one-shot events (e.g. `piece_locked`, `game_over`). New cores SHOULD include `version: int` in the snapshot. See `docs/persistence.md` and `docs/architecture.md` § "Snapshot diffs, not signals".

### Tests — three layers, all required

1. **Unit** — pure logic. `tests/unit/`.
2. **Scene** — input → core → render. Use `Input.parse_input_event`.
3. **Integration** — scripted, deterministic-seed sessions. `tests/integration/`.

A fourth layer, **e2e-replay**, is manual / nightly only (not gated on PR CI): a scripted heuristic AI plays a full session and records video for human spot-check. See `docs/e2e-replay.md`.

## 6. Adding a new game

See `docs/adding-a-game.md`.

## 7. Don'ts

- No Flutter / Unity / React Native — Godot is the decision.
- No C#/.NET Godot.
- Don't commit `.godot/` cache or build output (gitignored).
- Don't open a PR without a backing issue.
- Don't mark a card Done with red CI.

## 8. Learning log

Goal: don't repeat the same mistake twice. Get smarter over time.

**When to write a learning note.** You hit ≥ 2 failed attempts of the same kind in this session (wrong tool flag, wrong assumption about an API, wrong determinism source, wrong CI invocation, …) before landing on what worked. One-shot fixes don't qualify — only patterns that *cost time* and that future-you would benefit from knowing up front.

**How.**

1. Create `docs/learning/yyyy-mm-dd-<short-english-slug>.md` with two sections:
   - **Context** — what you were trying to do, what kept failing, why the wrong attempts looked plausible.
   - **Solution** — what actually worked, and the underlying reason (so the lesson generalizes).
2. Append one line to `docs/learning/index.md`:
   `- [yyyy-mm-dd-<slug>.md](yyyy-mm-dd-<slug>.md) — <one-sentence context>. <one-sentence solution>.`
3. Keep both terse. The note is a tripwire for next time, not a postmortem.

**When to read.** At the start of any task that touches an area you've previously logged about (Godot CI, movie maker, determinism, board automation, …), skim `docs/learning/index.md` first.
