#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/dist/OpenCodexTray.app"

verify_resources() {
  local output
  output="$(perl -e 'alarm shift @ARGV; exec @ARGV' 10 "$@")" \
    || { print -u2 -- "FAIL: resource verification command failed: $*"; exit 1; }
  [[ "$output" == "Resources OK" ]] \
    || { print -u2 -- "FAIL: unexpected resource verification output: $output"; exit 1; }
}

"$ROOT/scripts/build-app.sh" >/dev/null

WIDGET="$APP/Contents/PlugIns/OpenCodexWidget.appex"
test -x "$WIDGET/Contents/MacOS/OpenCodexWidget"
test "$(plutil -extract CFBundleIdentifier raw -o - "$WIDGET/Contents/Info.plist")" = "local.opencodex.quota-tray.widget"
test -f "$WIDGET/Contents/Resources/ProviderIcon-claude.svg"
test -f "$WIDGET/Contents/Resources/ProviderIcon-codex.svg"
test -f "$WIDGET/Contents/Resources/CodexBar-LICENSE.txt"
codesign --verify --deep --strict --verbose=4 "$APP"

if strings -a "$APP/Contents/MacOS/OpenCodexTray" | grep -Eq -- '/Users/|\.build/'; then
  print -u2 -- "FAIL: release binary contains a local build path"
  exit 1
fi

verify_resources "$APP/Contents/MacOS/OpenCodexTray" --verify-resources
swift build --package-path "$ROOT" -c release --product OpenCodexTray >/dev/null
verify_resources swift run --package-path "$ROOT" -c release --skip-build OpenCodexTray --verify-resources

print -- "PASS: release artifact is path-clean and resolves resources"
