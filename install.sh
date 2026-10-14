#!/bin/zsh
# FOKS TTS source installer for Apple silicon Macs.
#
#   ./install.sh               install everything and build the app
#   ./install.sh --no-app      set up only the Python environment and the Kokoro model
#   ./install.sh --force       rebuild the environment and re-download the model
#
# What it does (idempotent; safe to re-run):
#   1. checks macOS 14+, Apple silicon, the Command Line Tools and `uv`
#   2. creates ~/Library/Application Support/FOKS-TTS/venv from the hash-locked requirements/core.lock
#      (a uv-managed Python 3.13; no system Python, no GPL packages)
#   3. downloads the Kokoro-82M model at a pinned revision into .../FOKS-TTS/models/kokoro and verifies
#      its SHA-256
#   4. speaks a test sentence completely offline
#   5. builds "FOKS TTS.app" and installs it to ~/Applications (also registers the Services-menu entry)
#
# Network is used only in steps 2 and 3 (PyPI, GitHub for the spaCy model and Python, Hugging Face for the model).
# An existing setup, including a symlinked developer setup, is verified and left alone unless it is a real
# directory and you pass --force.
#
# Environment (read by this script, not by the app):
#   FOKS_TTS_HOME   install somewhere other than ~/Library/Application Support/FOKS-TTS. The app reads only the
#                   default location, so it is not built when this is set. Apps launched from Finder do not see
#                   shell variables anyway: point the app at other locations in its Settings > Engine locations.
set -euo pipefail

HERE=${0:A:h}
DEFAULT_HOME="$HOME/Library/Application Support/FOKS-TTS"
FOKS_HOME=${FOKS_TTS_HOME:-$DEFAULT_HOME}
MODEL_REPO="mlx-community/Kokoro-82M-bf16"
MODEL_REV="a71e4d38b236d968966a2002c4c895dbd12b1c3c"
MODEL_WEIGHTS="kokoro-v1_0.safetensors"
MODEL_SHA256="4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8"

BUILD_APP=1 FORCE=0
for arg in "$@"; do
  case $arg in
    --no-app) BUILD_APP=0 ;;
    --force)  FORCE=1 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg (try --help)"; exit 2 ;;
  esac
done

say()  { print -P "%F{green}==>%f $*"; }
warn() { print -P "%F{yellow}!!%f  $*"; }
die()  { print -P "%F{red}error:%f $*" >&2; exit 1; }

# ---- 1. prerequisites -------------------------------------------------------------------------------------
[[ $(uname -s) == Darwin ]] || die "FOKS TTS is macOS only."
[[ $(uname -m) == arm64 ]]  || die "FOKS TTS needs Apple silicon (the voice engine uses MLX)."
(( $(sw_vers -productVersion | cut -d. -f1) >= 14 )) || die "macOS 14 or newer is required."

if (( BUILD_APP )); then
  if [[ $FOKS_HOME != $DEFAULT_HOME ]]; then
    warn "FOKS_TTS_HOME is set to a custom location; the app only reads the default one, so the app will not be built."
    BUILD_APP=0
  elif ! command -v swiftc >/dev/null; then
    die "No Swift compiler found. Run: xcode-select --install   (then re-run this script)"
  fi
fi

if ! command -v uv >/dev/null; then
  if command -v brew >/dev/null; then
    say "Installing uv with Homebrew"
    brew install uv
  else
    die "uv is required. Install it with Homebrew (brew install uv) or see https://docs.astral.sh/uv/ and re-run."
  fi
fi
export UV_PYTHON_PREFERENCE=only-managed     # use uv's own Python, never Homebrew's or the system one

# ---- 2. Python environment --------------------------------------------------------------------------------
VENV="$FOKS_HOME/venv"
PY="$VENV/bin/python"
mkdir -p "$FOKS_HOME/models"

if [[ -e $VENV || -L $VENV ]] && (( ! FORCE )); then
  say "Python environment already present ($VENV); verifying"
elif [[ -L $VENV ]]; then
  warn "$VENV is a symlink (a developer setup); leaving it alone even with --force"
else
  [[ -e $VENV ]] && { say "Removing the existing environment (--force)"; rm -rf "$VENV"; }
  say "Creating the Python 3.13 environment (this downloads about 460 MB the first time)"
  uv venv --python 3.13 "$VENV"
  uv pip install --python "$PY" --require-hashes --no-deps -r "$HERE/requirements/core.lock"
fi
"$PY" -c "import mlx.core, mlx_audio, misaki, scipy" 2>/dev/null \
  || die "The Python environment at $VENV is incomplete. Re-run with --force."

# ---- 3. Kokoro model --------------------------------------------------------------------------------------
MODEL="$FOKS_HOME/models/kokoro"
if [[ -f $MODEL/config.json && -e $MODEL/$MODEL_WEIGHTS && -d $MODEL/voices ]] && (( ! FORCE )); then
  say "Kokoro model already present; verifying"
elif [[ -L $MODEL ]]; then
  warn "$MODEL is a symlink (a developer setup); leaving it alone even with --force"
else
  [[ -e $MODEL ]] && rm -rf "$MODEL"
  say "Downloading the Kokoro-82M model (about 370 MB, pinned revision ${MODEL_REV[1,8]})"
  MODEL_REPO=$MODEL_REPO MODEL_REV=$MODEL_REV MODEL_DIR=$MODEL HF_HUB_DISABLE_TELEMETRY=1 "$PY" - <<'PYEOF'
import os
from huggingface_hub import snapshot_download
snapshot_download(repo_id=os.environ["MODEL_REPO"], revision=os.environ["MODEL_REV"], local_dir=os.environ["MODEL_DIR"],
                  allow_patterns=["config.json", "kokoro-v1_0.safetensors", "voices/*.safetensors", "README.md"])
PYEOF
fi
say "Verifying the model's SHA-256"
actual=$(shasum -a 256 "$MODEL/$MODEL_WEIGHTS" | cut -d' ' -f1)
[[ $actual == $MODEL_SHA256 ]] || die "Model checksum mismatch (got $actual). Delete $MODEL and re-run."

# ---- 4. offline smoke test --------------------------------------------------------------------------------
say "Speaking a test sentence offline"
FOKS_TTS_HOME=$FOKS_HOME HF_HUB_OFFLINE=1 PYTHONPATH=$HERE "$PY" - <<'PYEOF'
import tts_core as core
words = "FOKS TTS is installed and speaking offline.".split()
secs = sum(len(a) for a, _ in core.chunk_stream(words, "af_heart")) / core.SR
assert secs > 1, "no audio produced"
print(f"    ok: {secs:.1f} s of audio, eSpeak add-on {'present' if core.HAS_ESPEAK else 'not installed (optional)'}")
PYEOF

# ---- 5. the app -------------------------------------------------------------------------------------------
if (( BUILD_APP )); then
  say "Building FOKS TTS.app"
  "$HERE/app/build_app.sh"
  say "Installing to ~/Applications and registering the Services entry"
  "$HERE/app/install_local.sh"
  cat <<EOF

Done. Next steps:
  1. Open "FOKS TTS" from ~/Applications (it lives in the menu bar; if the icon is hidden on a notched display,
     the hotkeys still work).
  2. In its Settings, grant Accessibility (to read windows and selections directly) and, for area and
     full-screen reading, Screen Recording.
  3. Try Control-Option-Command-T on selected text, or -W / -A / -S for a window, an area, or the whole screen.
Optional: Settings > Extended pronunciation installs a separate GPL add-on for names and jargon.
EOF
else
  say "Environment and model are ready. Run ./install.sh (without --no-app) to build the app."
fi
