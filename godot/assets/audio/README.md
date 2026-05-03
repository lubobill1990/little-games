# Audio assets

Layout, fetch policy, and licensing notes for audio used by the games in this
repo. **Audio binaries (`*.mp3`, `*.ogg`, `*.wav`) are gitignored** — they
never live in the repo. See issue #43 for context.

## Layout

```
godot/assets/audio/
  README.md              ← this file
  tetris/                ← gitignored, populated locally by fetch script
    move.mp3, rotate.mp3, ...
    Korobeiniki-FVR-01.mp3
    *.import             ← also gitignored; editor regenerates on first open
```

Streams are loaded from disk at runtime by the `SfxLibrary` and `BgmPlayer`
autoloads. **No `AudioStream` resource is referenced from any committed
`.tscn` or `.tres`.** A CI step grep-guards this — if a future PR inlines a
stream reference, the build fails.

## Tetris (`assets/audio/tetris/`)

The Tetris SFX/BGM are captured from `play.tetris.com` and are **proprietary
assets of The Tetris Company**. They are licensed for **personal/local
testing only** in this project — not for promotion, public distribution, or
inclusion in any shipped artifact.

Hard guarantees enforced by the repo:

1. The directory is in `.gitignore`. `git ls-files | grep -iE
   '\.(mp3|ogg|wav)$'` returns nothing — CI fails if it ever does.
2. The web export (`gh-pages`) excludes the directory at the *config* layer:
   `godot/export_presets.cfg` carries `exclude_filter=assets/audio/tetris/*`
   on every preset. CI greps the file — if a developer removes the line, the
   build fails.
3. With the directory empty (fresh clone, CI), the game boots and runs
   without crashing. `SfxLibrary.register()` gates `load()` with
   `FileAccess.file_exists()` so missing assets don't trigger engine-level
   resource-loader errors. The library emits at most one summary
   `push_warning` per game per boot.

### Fetching

```bash
# Default — direct URL fetch (the URL list is embedded in the script).
scripts/dev/fetch_tetris_audio.sh

# If the cache-buster querystring expires and direct fetch 404s, capture a
# fresh HAR from play.tetris.com (DevTools → Network → Save All as HAR with
# Content) and run:
scripts/dev/fetch_tetris_audio.sh --har path/to/file.har
```

The script writes into `godot/assets/audio/tetris/` and skips files that
already exist with non-zero size (idempotent).

### `.import` regeneration

Godot generates `*.import` sidecar files for every audio file when the editor
imports them. Both the audio binaries and their `.import` files are
gitignored. Open the project in the editor once after fetching to let it
generate the import metadata; thereafter the editor and the headless `--import`
step both reuse the cached `.godot/imported/` artefacts.

Headless CI never fetches the mp3s and never tries to import them — there's
nothing to import.
