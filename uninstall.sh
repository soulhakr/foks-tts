#!/bin/zsh
# Remove FOKS TTS: the app, its settings, and (after asking) its Python environment, model and logs.
# Symlinks are removed as links; whatever they point to (for example a developer's ~/AI folder) is never deleted.
set -uo pipefail

APP="$HOME/Applications/FOKS TTS.app"
FOKS_HOME="$HOME/Library/Application Support/FOKS-TTS"
LOGS="$HOME/Library/Logs/FOKS-TTS"

ask() { read -q "REPLY?$1 [y/N] " && { print; return 0; }; print; return 1; }

pkill -x FOKS-TTS 2>/dev/null
if [[ -d $APP ]]; then rm -rf "$APP" && echo "removed $APP"; fi
defaults delete local.soulhakr.foks-tts 2>/dev/null && echo "removed saved settings"
/usr/libexec/PlistBuddy -c "Delete :NSServicesStatus:local.soulhakr.foks-tts - Read Aloud with FOKS TTS - readAloud" \
  "$HOME/Library/Preferences/pbs.plist" 2>/dev/null && echo "removed the Services-menu switch"
/System/Library/CoreServices/pbs -update 2>/dev/null

if [[ -e $FOKS_HOME || -L $FOKS_HOME ]] && ask "Delete the Python environment and Kokoro model in $FOKS_HOME?"; then
  rm -rf "$FOKS_HOME" && echo "removed $FOKS_HOME"
fi
if [[ -d $LOGS ]] && ask "Delete the logs in $LOGS?"; then
  rm -rf "$LOGS" && echo "removed $LOGS"
fi
echo "Note: macOS keeps the Accessibility and Screen Recording entries; remove 'FOKS TTS' in System Settings > Privacy & Security if you like."
