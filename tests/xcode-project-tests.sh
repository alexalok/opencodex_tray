#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$(mktemp -d /tmp/opencodex-xcode-tests.XXXXXX)"
trap 'rm -rf "$DERIVED"' EXIT

WIDGET_BUILD_SETTINGS="$(xcodebuild \
  -project "$ROOT/OpenCodexTray.xcodeproj" \
  -target OpenCodexWidget \
  -configuration Debug \
  -showBuildSettings)"
if [[ "$WIDGET_BUILD_SETTINGS" != *$'ENABLE_APP_SANDBOX = YES'* ]]; then
  print -u2 -- "FAIL: OpenCodexWidget must enable App Sandbox in target build settings"
  exit 1
fi

HOST_BUILD_SETTINGS="$(xcodebuild \
  -project "$ROOT/OpenCodexTray.xcodeproj" \
  -target OpenCodexTray \
  -configuration Debug \
  -showBuildSettings)"
if [[ "$HOST_BUILD_SETTINGS" != *$'CODE_SIGN_ENTITLEMENTS = Resources/OpenCodexTray.entitlements'* ]]; then
  print -u2 -- "FAIL: OpenCodexTray must sign with App Group entitlements"
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
WIDGET="$APP/Contents/PlugIns/OpenCodexWidget.appex"
test -x "$APP/Contents/MacOS/OpenCodexTray"
test -d "$WIDGET"
test -x "$WIDGET/Contents/MacOS/OpenCodexWidget"
test "$(plutil -extract CFBundleVersion raw -o - "$APP/Contents/Info.plist")" = "913"
test "$(plutil -extract CFBundleVersion raw -o - "$WIDGET/Contents/Info.plist")" = "913"
test "$(plutil -extract NSExtension.NSExtensionPointIdentifier raw -o - "$WIDGET/Contents/Info.plist")" = "com.apple.widgetkit-extension"
test -f "$APP/Contents/Resources/ProviderIcon-claude.svg"
test -f "$APP/Contents/Resources/ProviderIcon-codex.svg"
test -f "$APP/Contents/Resources/CodexBar-LICENSE.txt"
test -f "$WIDGET/Contents/Resources/ProviderIcon-claude.svg"
test -f "$WIDGET/Contents/Resources/ProviderIcon-codex.svg"
test -f "$WIDGET/Contents/Resources/CodexBar-LICENSE.txt"
test "$(plutil -extract 'com\.apple\.security\.app-sandbox' raw -o - "$ROOT/Resources/OpenCodexWidget.entitlements")" = "true"
test "$(plutil -extract 'com\.apple\.security\.network\.client' raw -o - "$ROOT/Resources/OpenCodexWidget.entitlements")" = "true"
test "$(plutil -extract 'com\.apple\.security\.application-groups'.0 raw -o - "$ROOT/Resources/OpenCodexWidget.entitlements")" = "KTNPDHXXV3.opencodex.quota-tray.shared"
test "$(plutil -extract 'com\.apple\.security\.application-groups'.0 raw -o - "$ROOT/Resources/OpenCodexTray.entitlements")" = "KTNPDHXXV3.opencodex.quota-tray.shared"
if plutil -extract 'com\.apple\.security\.temporary-exception.files.home-relative-path.read-only' raw -o - "$ROOT/Resources/OpenCodexWidget.entitlements" >/dev/null 2>&1; then
  print -u2 -- "FAIL: widget must not rely on home-directory temporary exceptions"
  exit 1
fi

if rg -n 'OpenCodexPausing|OpenCodexPauseClient|pauseAccount|/pause' "$ROOT/Sources/OpenCodexWidget"; then
  print -u2 -- "FAIL: widget source contains pause capability"
  exit 1
fi

if rg -n 'WorkerConfiguration\.load|AdminTokenReader' "$ROOT/Sources/OpenCodexWidget"; then
  print -u2 -- "FAIL: widget must load connection details from App Group store"
  exit 1
fi

print -- "PASS: Xcode app embeds WidgetKit extension"
