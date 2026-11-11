#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$(mktemp -d /tmp/opencodex-xcode-tests.XXXXXX)"
trap 'rm -rf "$DERIVED"' EXIT

if rg -n -i 'widget|application-groups' "$ROOT/OpenCodexTray.xcodeproj" "$ROOT/Resources" "$ROOT/Sources" "$ROOT/scripts"; then
  print -u2 -- "FAIL: widget or App Group remnants remain"
  exit 1
fi

xcodebuild \
  -project "$ROOT/OpenCodexTray.xcodeproj" \
  -scheme OpenCodexTray \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED" \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO \
  CURRENT_PROJECT_VERSION=913 \
  build

APP="$DERIVED/Build/Products/Release/OpenCodexTray.app"
test -x "$APP/Contents/MacOS/OpenCodexTray"
test ! -e "$APP/Contents/PlugIns"
test "$(plutil -extract CFBundleVersion raw -o - "$APP/Contents/Info.plist")" = "913"
test -f "$APP/Contents/Resources/ProviderIcon-claude.svg"
test -f "$APP/Contents/Resources/ProviderIcon-codex.svg"
test -f "$APP/Contents/Resources/ProviderIcon-zai.svg"
test -f "$APP/Contents/Resources/CodexBar-LICENSE.txt"

print -- "PASS: Xcode app builds without extensions"
