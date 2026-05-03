#!/usr/bin/env bash
# E2E replay runner. Boots Godot in movie-maker mode, plays Tetris with a
# scripted heuristic AI, writes an .ogv recording + .json sidecar.
#
# Usage:
#   scripts/e2e/run.sh tetris <seed> [--mp4] [--max-pieces N]
#
# Headless caveat: movie maker mode requires a rendering device. On Linux we
# auto-wrap with `xvfb-run -a` if available; otherwise we error out. macOS /
# Windows run direct.
#
# Output:
#   build/e2e/<game>-<seed>-<shortsha>.ogv
#   build/e2e/<game>-<seed>-<shortsha>.json
#   build/e2e/<game>-<seed>-<shortsha>.mp4   (only with --mp4 + ffmpeg present)
#
# Determinism contract: same seed + same commit → byte-identical .json sidecar
# (sorted keys, \n line endings). Video bytes are NOT asserted.

set -euo pipefail

# --- Args ----------------------------------------------------------------
GAME="${1:-}"
SEED="${2:-}"
shift || true
shift || true

WANT_MP4=0
MAX_PIECES=200
for a in "$@"; do
  case "$a" in
    --mp4) WANT_MP4=1 ;;
    --max-pieces=*) MAX_PIECES="${a#--max-pieces=}" ;;
    --max-pieces) ;;  # ignore bare flag (paired arg form not supported here)
  esac
done
if [ -z "$GAME" ] || [ -z "$SEED" ]; then
  echo "usage: $0 <game> <seed> [--mp4] [--max-pieces=N]" >&2
  exit 2
fi
if [ "$GAME" != "tetris" ]; then
  echo "error: only 'tetris' is supported in this PR (see #24 scope)" >&2
  exit 2
fi

# Allow CI / users to override via env.
WANT_MP4="${E2E_MP4:-$WANT_MP4}"

# --- Paths ---------------------------------------------------------------
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_PROJECT="$ROOT_DIR/godot"
OUT_DIR="$ROOT_DIR/build/e2e"
mkdir -p "$OUT_DIR"

SHORT_SHA="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
FULL_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
STEM="$OUT_DIR/${GAME}-${SEED}-${SHORT_SHA}"
OGV="$STEM.ogv"
JSON="$STEM.json"
MP4="$STEM.mp4"

# --- Pick Godot ----------------------------------------------------------
GODOT_BIN="${GODOT:-godot}"
if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  echo "error: '$GODOT_BIN' not on PATH (set GODOT env var)" >&2
  exit 1
fi

# --- Wrap with xvfb on Linux --------------------------------------------
WRAPPER=()
if [ "$(uname)" = "Linux" ]; then
  if ! command -v xvfb-run >/dev/null 2>&1; then
    echo "error: xvfb-run not installed; movie maker requires a display" >&2
    echo "hint: apt install xvfb" >&2
    exit 1
  fi
  WRAPPER=(xvfb-run -a)
fi

# --- Run Godot in movie-maker mode --------------------------------------
# `--write-movie` is the Godot 4.6 movie-maker mode flag; it forces fixed-fps
# rendering (Godot defaults to 60). The runner scene is loaded directly via
# --main-pack-style scene path (not the project's main_scene autoload).
echo "[e2e] writing $OGV (seed=$SEED, max_pieces=$MAX_PIECES, sha=$SHORT_SHA)"
"${WRAPPER[@]}" "$GODOT_BIN" --path "$GODOT_PROJECT" \
  --write-movie "$OGV" \
  res://scripts/e2e/runner.tscn \
  -- \
  --seed="$SEED" \
  --max-pieces="$MAX_PIECES" \
  --commit="$FULL_SHA" \
  --sidecar="$JSON"

# Sanity gate: non-empty outputs.
if [ ! -s "$OGV" ]; then
  echo "error: $OGV is empty or missing" >&2
  exit 1
fi
if [ ! -s "$JSON" ]; then
  echo "error: $JSON is empty or missing" >&2
  exit 1
fi
echo "[e2e] ogv: $(stat -c %s "$OGV" 2>/dev/null || stat -f %z "$OGV") bytes"
echo "[e2e] json: $(stat -c %s "$JSON" 2>/dev/null || stat -f %z "$JSON") bytes"

# --- Optional mp4 transcode ---------------------------------------------
if [ "$WANT_MP4" = "1" ]; then
  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "warn: ffmpeg not installed; skipping mp4 transcode" >&2
  else
    echo "[e2e] transcoding to $MP4"
    ffmpeg -y -i "$OGV" -c:v libx264 -pix_fmt yuv420p -c:a aac "$MP4" 2>&1 | tail -3
  fi
fi

echo "[e2e] done."
