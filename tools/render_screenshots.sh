#!/bin/zsh
# Regenerate the README images in docs/ (settings-light.png, settings-dark.png, menubar-icon.png).
#
#   tools/render_screenshots.sh [output-dir]      default: docs/
#
# The images are rendered from the real SwiftUI views, not captured from a screen. The harness runs against a demo home
# (/Users/Shared/foks-demo, deleted afterwards) so the paths in the Settings dialog show no real user name.
# Needs the Command Line Tools and an installed Kokoro model (only to copy the voice file names; the files are empty).
set -euo pipefail

HERE=${0:A:h}
ROOT=${HERE:h}
OUT=${1:-$ROOT/docs}
DEMO=/Users/Shared/foks-demo
WORK=$(mktemp -d "${TMPDIR:-/tmp}/foks-screens.XXXXXX")
trap 'rm -rf "${DEMO:?}" "${WORK:?}"' EXIT

REAL_VOICES="${FOKS_TTS_HOME:-$HOME/Library/Application Support/FOKS-TTS}/models/kokoro/voices"
[[ -d $REAL_VOICES ]] || { echo "No installed model at $REAL_VOICES (run ./install.sh first)"; exit 1; }

# demo home: an executable "python", a model folder and one empty file per voice, so Settings shows found status lines
rm -rf "${DEMO:?}"
mkdir -p "$DEMO/Library/Application Support/FOKS-TTS/venv/bin" "$DEMO/Library/Application Support/FOKS-TTS/models/kokoro/voices"
FH="$DEMO/Library/Application Support/FOKS-TTS"
: > "$FH/venv/bin/python"; chmod +x "$FH/venv/bin/python"
echo '{}' > "$FH/models/kokoro/config.json"
for f in "$REAL_VOICES"/*.safetensors; do : > "$FH/models/kokoro/voices/${f:t}"; done

echo "Compiling the harness"
SRC=(${(f)"$(find "$ROOT/app/Sources" -name '*.swift' ! -name main.swift | sort)"})
swiftc -swift-version 5 -O -o "$WORK/render" $SRC "$HERE/screenshots/main.swift" 2>&1 | grep -E 'error' || true
[[ -x $WORK/render ]] || { echo "compile failed"; exit 1; }

mkdir -p "$OUT"
CFFIXED_USER_HOME=$DEMO "$WORK/render" "$OUT" "$ROOT/app/Icon/MenuBarIcon@2x.png"
