# Audio assets

Layout and fetch notes for audio used by the games in this repo.

## Layout

```
godot/assets/audio/
  README.md              ← this file
  tetris/                ← committed mp3s + Godot-generated .import sidecars
    move.mp3, rotate.mp3, ...
    Korobeiniki-FVR-01.mp3
```

Streams are loaded from disk at runtime by the `SfxLibrary` and `BgmPlayer`
autoloads (no `AudioStream` resources in committed `.tscn`/`.tres`).

## Tetris (`assets/audio/tetris/`)

Captured from `play.tetris.com`. Per project owner's decision (#56), the
mp3s and their `.import` sidecars are checked into the repo so fresh
clones and the web export are audible without running the fetch script.

> ⚠️ Licensing note: these assets originated from The Tetris Company.
> Distribute / redistribute at your own risk.

### Re-fetching (only if you need fresh files)

```bash
# Default — direct URL fetch (URLs embedded in the script).
scripts/dev/fetch_tetris_audio.sh

# If cache-buster URLs 404, capture a HAR from play.tetris.com
# (DevTools → Network → Save All as HAR with Content) and run:
scripts/dev/fetch_tetris_audio.sh --har path/to/file.har
```

Idempotent — skips files that already exist with non-zero size.

### `.import` sidecars

Godot generates `*.import` sidecar files when the editor first imports each
mp3. They are committed alongside the binaries so headless CI and fresh
clones don't need a separate editor pass.
