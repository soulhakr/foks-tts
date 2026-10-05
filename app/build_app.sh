#!/bin/zsh
# Build OfflineTTS.app (menubar app) locally and ad-hoc sign it. Output: build/OfflineTTS.app
set -e
cd "${0:A:h}"
# The Command Line Tools SDK lacks the SwiftUI macro plugin; prefer full Xcode when present.
[[ -d /Applications/Xcode.app ]] && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
APP=build/OfflineTTS.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -o "$APP/Contents/MacOS/OfflineTTS" Sources/*.swift
cp Info.plist "$APP/Contents/Info.plist"
cp tts_worker.py ../tts_core.py "$APP/Contents/Resources/"
codesign --force --sign - --identifier local.soulhakr.offline-tts "$APP"
echo "built $APP"
