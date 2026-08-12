#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
swift build --package-path "$ROOT" -c release --product OpenCodexTray
BIN_DIR="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
APP="$ROOT/dist/OpenCodexTray.app"

mkdir -p "$APP/Contents/MacOS"
install -m 755 "$BIN_DIR/OpenCodexTray" "$APP/Contents/MacOS/OpenCodexTray"
install -m 644 "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
install -m 644 "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
RESOURCE_BUNDLE="$BIN_DIR/OpenCodexPauseWorker_OpenCodexTray.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  mkdir -p "$APP/Contents/Resources"
  rm -rf "$APP/Contents/Resources/${RESOURCE_BUNDLE:t}"
  cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
fi
codesign --force --sign - "$APP"

echo "$APP"
