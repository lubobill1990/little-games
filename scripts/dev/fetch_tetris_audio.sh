#!/usr/bin/env bash
# Fetch Tetris audio (SFX + BGM) from play.tetris.com or a captured HAR into
# godot/assets/audio/tetris/. Local/personal use only — see issue #43 and
# godot/assets/audio/README.md for licensing constraints.
#
# Modes:
#   fetch_tetris_audio.sh                  → direct URL fetch (default)
#   fetch_tetris_audio.sh --urls           → same as default
#   fetch_tetris_audio.sh --har <path>     → extract from a HAR file
#   fetch_tetris_audio.sh --force          → re-download even if file exists
#
# Both modes write to godot/assets/audio/tetris/ relative to the repo root,
# unless [outdir] is given as a positional after the flags.

set -euo pipefail

# --- locate repo root (so the script works whether invoked from anywhere) ---
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." >/dev/null 2>&1 && pwd)"
DEFAULT_OUT="$REPO_ROOT/godot/assets/audio/tetris"

# --- 17 source URLs (cache-buster suffix may stop resolving over time) ---
URLS=(
  "https://play.tetris.com/tetris-game-package/game/Tetrion-resources/project-Marathon/sounds/sounds-01/move.mp3?cbid=62B1EB587D30B208a"
  "https://play.tetris.com/tetris-game-package/game/Tetrion-resources/project-Marathon/sounds/sounds-01/rotate.mp3?cbid=62B1EB587D30B208a"
  "https://play.tetris.com/tetris-game-package/game/Tetrion-resources/project-Marathon/sounds/sounds-01/hardDrop.mp3?cbid=62B1EB587D30B208a"
  "https://play.tetris.com/tetris-game-package/game/Tetrion-resources/project-Marathon/sounds/sounds-01/lock.mp3?cbid=62B1EB587D30B208a"
  "https://play.tetris.com/tetris-game-package/game/Tetrion-resources/project-Marathon/sounds/sounds-01/lineClear.mp3?cbid=62B1EB587D30B208a"
  "https://play.tetris.com/tetris-game-package/game/Tetrion-resources/project-Marathon/sounds/sounds-01/tetris.mp3?cbid=62B1EB587D30B208a"
  "https://play.tetris.com/tetris-game-package/game/Tetrion-resources/project-Marathon/sounds/sounds-01/backToBackTetris.mp3?cbid=62B1EB587D30B208a"
  "https://play.tetris.com/tetris-game-package/game/Tetrion-resources/project-Marathon/sounds/sounds-01/collapse.mp3?cbid=62B1EB587D30B208a"
  "https://play.tetris.com/tetris-game-package/game/Tetrion-resources/project-Marathon/sounds/sounds-01/levelUp.mp3?cbid=62B1EB587D30B208a"
  "https://play.tetris.com/tetris-game-package/game/Tetrion-resources/project-Marathon/sounds/sounds-01/hold.mp3?cbid=62B1EB587D30B208a"
  "https://play.tetris.com/tetris-game-package/game/Tetrion-resources/project-Marathon/sounds/sounds-01/inputFailed.mp3?cbid=62B1EB587D30B208a"
  "https://play.tetris.com/tetris-game-package/game/Tetrion-resources/project-Marathon/sounds/sounds-01/blockout.mp3?cbid=62B1EB587D30B208a"
  "https://play.tetris.com/tetris-game-package/game/Tetrion-resources/project-Marathon/sounds/sounds-01/win.mp3?cbid=62B1EB587D30B208a"
  "https://play.tetris.com/tetris-game-package/game/Tetrion-resources/project-Marathon/music/remote/Korobeiniki-FVR-01.mp3?cbid=62B1EB587D30B208a"
  "https://play.tetris.com/tetris-game-package/game/Tetrion-resources/project-Marathon/music/remote/Korobeiniki-BR-01.mp3?cbid=62B1EB587D30B208a"
  "https://play.tetris.com/tetris-game-package/game/Tetrion-resources/project-Marathon/music/remote/Korobeiniki-CN-01.mp3?cbid=62B1EB587D30B208a"
  "https://play.tetris.com/tetris_theme_music.mp3"
)

UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
REFERER="https://play.tetris.com/"

mode="urls"
har=""
force=0
outdir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --urls) mode="urls"; shift;;
    --har)
      mode="har"
      [[ -n "${2:-}" ]] || { echo "--har needs a path"; exit 2; }
      har="$2"; shift 2;;
    --force) force=1; shift;;
    -h|--help)
      sed -n '1,15p' "$0"; exit 0;;
    *)
      [[ -z "$outdir" ]] || { echo "unexpected arg: $1"; exit 2; }
      outdir="$1"; shift;;
  esac
done

outdir="${outdir:-$DEFAULT_OUT}"
mkdir -p "$outdir"

# basename minus the ?cbid=... querystring
strip_qs() {
  local url="$1"
  local last="${url##*/}"
  echo "${last%%\?*}"
}

fetch_one() {
  local url="$1"
  local name
  name="$(strip_qs "$url")"
  local target="$outdir/$name"
  if [[ -s "$target" && $force -eq 0 ]]; then
    echo "skip (exists) $name"
    return 0
  fi
  if curl -fSL --max-time 60 \
       -A "$UA" -H "Referer: $REFERER" \
       -o "$target" "$url"; then
    local size
    size=$(stat -c%s "$target" 2>/dev/null || stat -f%z "$target" 2>/dev/null || echo 0)
    if [[ "$size" -eq 0 ]]; then
      echo "warn: 0-byte download for $name; removing"
      rm -f "$target"
      return 1
    fi
    echo "got $name ($size bytes)"
    return 0
  fi
  rm -f "$target"
  echo "warn: $name failed — URL may be stale; capture a fresh HAR and re-run with --har"
  return 1
}

if [[ "$mode" == "urls" ]]; then
  echo "writing to $outdir"
  ok=0; fail=0
  for u in "${URLS[@]}"; do
    if fetch_one "$u"; then ok=$((ok+1)); else fail=$((fail+1)); fi
  done
  echo "done: $ok ok, $fail failed"
  [[ $fail -eq 0 ]] || exit 1
  exit 0
fi

# --- HAR mode (Node script inline) ---
[[ -f "$har" ]] || { echo "HAR not found: $har"; exit 2; }
command -v node >/dev/null || { echo "HAR mode requires node"; exit 2; }

node - "$har" "$outdir" <<'NODE'
const fs = require('fs');
const path = require('path');
const [, , harPath, outdir] = process.argv;
const har = JSON.parse(fs.readFileSync(harPath, 'utf8'));
const entries = (har.log && har.log.entries) || [];
let ok = 0, fail = 0;
for (const e of entries) {
  const url = e.request && e.request.url;
  if (!url || !/\.mp3(\?|$)/i.test(url)) continue;
  const status = (e.response && e.response.status) || 0;
  if (status === 206) {
    console.warn('skip 206 partial:', url);
    fail++;
    continue;
  }
  const content = e.response && e.response.content;
  if (!content || typeof content.text !== 'string') {
    console.warn('skip no body:', url);
    fail++;
    continue;
  }
  const name = path.basename(url.split('?')[0]);
  const target = path.join(outdir, name);
  let buf;
  if (content.encoding === 'base64') {
    buf = Buffer.from(content.text, 'base64');
  } else {
    console.warn('warn: non-base64 encoding', content.encoding || '(none)', 'for', name);
    buf = Buffer.from(content.text, 'binary');
  }
  fs.writeFileSync(target, buf);
  console.log('got', name, buf.length, 'bytes');
  ok++;
}
console.log(`done: ${ok} ok, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
NODE
