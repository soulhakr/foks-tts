#!/bin/zsh
# Build OfflineTTS.app (menubar app) locally and ad-hoc sign it. Output: build/OfflineTTS.app
set -e
cd "${0:A:h}"
# Builds with the Command Line Tools alone (xcode-select --install); full Xcode is not required.
APP=build/OfflineTTS.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -o "$APP/Contents/MacOS/OfflineTTS" Sources/*.swift
cp Info.plist "$APP/Contents/Info.plist"
cp tts_worker.py ../tts_core.py "$APP/Contents/Resources/"
cp ../requirements/optional-gpl-pronunciation.lock "$APP/Contents/Resources/"
codesign --force --sign - --identifier local.soulhakr.offline-tts "$APP"
echo "built $APP"
