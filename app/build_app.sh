#!/bin/zsh
# Build "FOKS TTS.app" (menubar app) locally and ad-hoc sign it. Output: build/FOKS TTS.app
set -e
cd "${0:A:h}"
# Builds with the Command Line Tools alone (xcode-select --install); full Xcode is not required.
APP="build/FOKS TTS.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -o "$APP/Contents/MacOS/FOKS-TTS" Sources/*.swift
cp Info.plist "$APP/Contents/Info.plist"
cp tts_worker.py ../tts_core.py "$APP/Contents/Resources/"
cp ../requirements/optional-gpl-pronunciation.lock "$APP/Contents/Resources/"
cp Icon/AppIcon.icns Icon/MenuBarIcon.png "Icon/MenuBarIcon@2x.png" "$APP/Contents/Resources/"
codesign --force --sign - --identifier local.soulhakr.foks-tts "$APP"
echo "built $APP"
