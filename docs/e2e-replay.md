# E2E Replay Layer

A scripted heuristic AI plays a full Tetris session, the run is recorded as video, and a human spot-checks it. Fourth test layer above unit / scene / integration: catches feel, render, HUD, audio-sync, and game-over regressions that pass green CI.

## Quick start (local)

```bash
# Tetris, seed 4242, default 200-piece cap, .ogv only.
scripts/e2e/run.sh tetris 4242

# Add an mp4 transcode (requires ffmpeg).
scripts/e2e/run.sh tetris 4242 --mp4

# Smaller / faster smoke run.
scripts/e2e/run.sh tetris 4242 --max-pieces=40
```

Outputs land in `build/e2e/`:

```
build/e2e/tetris-4242-<shortsha>.ogv    # Theora/Vorbis video
build/e2e/tetris-4242-<shortsha>.json   # action log + score + commit sha
build/e2e/tetris-4242-<shortsha>.mp4    # only with --mp4 + ffmpeg
```

The Linux script auto-wraps Godot with `xvfb-run`. macOS / Windows run direct.

## CI

Workflow `.github/workflows/e2e.yml` runs on `workflow_dispatch` + nightly cron (06:23 UTC). Artifacts uploaded with **14-day retention**. Never gated on PR CI — movie-mode rendering is expensive and the verdict is human-eye, not green-check.

To trigger manually: GitHub → Actions → "e2e" → "Run workflow". Optional inputs: seed (default `4242`), max_pieces (default `200`), mp4 (default `0`).

## Determinism contract

Same seed + same commit SHA → **byte-identical canonicalized action-log JSON** (sorted keys, `\n` line endings, integer score / lines / pieces). Video bytes are NOT asserted (encoder timing varies).

The canonicalization is enforced by `runner.gd` writing the sidecar via `JSON.stringify(doc, "\t", true)` — the second argument forces sorted keys.

If a determinism check ever fails, suspect:

- Non-seeded `randf()` somewhere in the input chain (search for it; the AI itself uses no RNG).
- Real-time clocks the AI reads (`Time.get_ticks_msec()`, `OS.get_ticks_usec()`) — none today, but a future game might add one.
- `Input.parse_input_event` queue lag (the runner uses `Input.action_press` directly to bypass it; if you add a parse-event path, retest determinism).

## Format choice — why OGV

Godot 4.6 movie maker writes OGV (Theora/Vorbis), AVI MJPEG, or PNG sequence:

| Format | Pros | Cons |
|---|---|---|
| **OGV** *(default)* | Audio included, modest file size (~few MB / 60 s), fixed-fps deterministic timing | Older codec; modern players support it but social-media uploaders sometimes don't |
| AVI MJPEG | Trivially decodable | No audio, hundreds of MB per minute |
| PNG sequence | Bit-identical frame bytes | No audio, no playable file, huge directory |

We default to OGV. `--mp4` opt-in re-encodes via `ffmpeg -c:v libx264 -pix_fmt yuv420p -c:a aac` for sharing.

## Headless caveat

**Movie maker requires a rendering device and is incompatible with `--headless`.** On Linux CI, `run.sh` and `e2e.yml` invoke Godot under `xvfb-run -a`. macOS / Windows run direct.

This is the reason e2e is a separate workflow from `ci.yml` — the GUT suite runs `--headless` and is incompatible with movie mode.

## Adding a second game's AI

Out of scope for #24. The pattern when the time comes:

1. Write `godot/scripts/e2e/<game>_ai.gd` mirroring `tetris_ai.gd`'s shape: a planner that emits an action stream from a snapshot of the per-game core.
2. Generalize `runner.gd` only when a second game actually exists — premature abstraction otherwise. Likely shape: read `--game=` from CLI, dispatch to a per-game runner module.
3. Update this document with the new smoke seed + acceptance bar.

The `next_action` signature on `tetris_ai.gd` is intentionally Tetris-shaped (returns a discrete StringName tied to InputManager actions); a real-time analog game (Breakout) will need a different interface (continuous paddle intent). Don't unify the two prematurely — wait until breakout's e2e lands and refactor with two real call sites in hand.

## Smoke seed

Default `seed=4242`. The integration test at `tests/integration/test_tetris_ai.gd` asserts the AI clears at least one line in 80 pieces on this seed; if a future weight tuning regresses that bar on `4242` specifically, **change the weights or pick a new seed and document it here** — do not silently swap seeds in CI.

## How to view artifacts

1. Trigger the e2e workflow (or wait for the nightly).
2. Download the artifact zip from the run page.
3. Play `<game>-<seed>-<sha>.ogv` in VLC / Chrome / Firefox. The `.json` sidecar is human-readable: open it in your editor to see the action sequence and final score.
4. Spot-check: did the score line up with what the AI did on screen? Are HUD values updating? Does the game-over flow play out cleanly?

If anything looks wrong, file an issue with the artifact attached and the seed reproducer.
