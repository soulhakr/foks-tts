#!/bin/zsh
# Install the built app into ~/Applications so macOS discovers its Services-menu entry, then refresh the
# Services cache. (Services are only picked up from apps in standard locations, not from a build folder.)
set -e
cd "${0:A:h}"
SRC="build/FOKS TTS.app"
[[ -d "$SRC" ]] || { echo "Build first: ./build_app.sh"; exit 1; }
DEST="$HOME/Applications/FOKS TTS.app"
mkdir -p "$HOME/Applications"
pkill -x FOKS-TTS 2>/dev/null || true
rm -rf "$DEST"
ditto "$SRC" "$DEST"
# Enable the service in both the app-menu Services submenu and the right-click menu (same switches as
# System Settings > Keyboard > Keyboard Shortcuts > Services > Text).
defaults write pbs NSServicesStatus -dict-add \
  "local.soulhakr.foks-tts - Read Aloud with FOKS TTS - readAloud" \
  '{ "enabled_context_menu" = 1; "enabled_services_menu" = 1; "presentation_modes" = { ContextMenu = 1; FinderPreview = 1; ServicesMenu = 1; TouchBar = 1; }; }'
/System/Library/CoreServices/pbs -update 2>/dev/null || true
echo "Installed: $DEST"
echo "Open it once, then in any app: select text > right-click > Services > Read Aloud with FOKS TTS."
echo "If it is not listed, tick it once in System Settings > Keyboard > Keyboard Shortcuts > Services > Text (you can also assign a shortcut there)."
