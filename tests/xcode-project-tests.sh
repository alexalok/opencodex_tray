#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$(mktemp -d /tmp/opencodex-xcode-tests.XXXXXX)"
trap 'rm -rf "$DERIVED"' EXIT

xcodebuild \
  -project "$ROOT/OpenCodexTray.xcodeproj" \
  -scheme OpenCodexTray \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED" \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$DERIVED/Build/Products/Release/OpenCodexTray.app"
WIDGET="$APP/Contents/PlugIns/OpenCodexWidget.appex"
test -x "$APP/Contents/MacOS/OpenCodexTray"
test -d "$WIDGET"
test -x "$WIDGET/Contents/MacOS/OpenCodexWidget"
test "$(plutil -extract NSExtension.NSExtensionPointIdentifier raw -o - "$WIDGET/Contents/Info.plist")" = "com.apple.widgetkit-extension"
test -f "$APP/Contents/Resources/ProviderIcon-claude.svg"
test -f "$APP/Contents/Resources/ProviderIcon-codex.svg"
test -f "$APP/Contents/Resources/CodexBar-LICENSE.txt"
test -f "$WIDGET/Contents/Resources/ProviderIcon-claude.svg"
test -f "$WIDGET/Contents/Resources/ProviderIcon-codex.svg"
test -f "$WIDGET/Contents/Resources/CodexBar-LICENSE.txt"
test "$(plutil -extract 'com\.apple\.security\.app-sandbox' raw -o - "$ROOT/Resources/OpenCodexWidget.entitlements")" = "true"
test "$(plutil -extract 'com\.apple\.security\.network\.client' raw -o - "$ROOT/Resources/OpenCodexWidget.entitlements")" = "true"

if rg -n 'OpenCodexPausing|OpenCodexPauseClient|pauseAccount|/pause' "$ROOT/Sources/OpenCodexWidget"; then
  print -u2 -- "FAIL: widget source contains pause capability"
  exit 1
fi

print -- "PASS: Xcode app embeds WidgetKit extension"
