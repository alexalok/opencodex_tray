#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
TEST_ROOT=""

cleanup() {
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
    rm -rf "$TEST_ROOT"
  fi
}
trap cleanup EXIT

fail() {
  print -u2 -- "FAIL: $1"
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected command log to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "expected command log not to contain: $needle"
}

make_fixture() {
  cleanup
  TEST_ROOT="$(mktemp -d /tmp/opencodex-build-tests.XXXXXX)"
  TEST_ROOT="${TEST_ROOT:A}"
  mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/Resources" "$TEST_ROOT/fake-bin" "$TEST_ROOT/swift-bin"
  cp "$PROJECT_ROOT/scripts/build-app.sh" "$TEST_ROOT/scripts/build-app.sh"
  touch "$TEST_ROOT/Resources/Info.plist" "$TEST_ROOT/Resources/AppIcon.icns"

  cat > "$TEST_ROOT/fake-bin/swift" <<'EOF'
#!/bin/zsh
set -euo pipefail
print -r -- "swift|$*" >> "$COMMAND_LOG"
mkdir -p "$FAKE_SWIFT_BIN/OpenCodexPauseWorker_OpenCodexTray.bundle"
touch "$FAKE_SWIFT_BIN/OpenCodexPauseWorker_OpenCodexTray.bundle/ProviderIcon.svg"
touch "$FAKE_SWIFT_BIN/OpenCodexTray"
chmod 755 "$FAKE_SWIFT_BIN/OpenCodexTray"
if [[ " $* " == *" --show-bin-path "* ]]; then
  print -r -- "$FAKE_SWIFT_BIN"
fi
if [[ "${FAKE_SWIFT_FAIL:-0}" == "1" ]]; then
  exit 42
fi
EOF

  cat > "$TEST_ROOT/fake-bin/codesign" <<'EOF'
#!/bin/zsh
set -euo pipefail
print -r -- "codesign|$*" >> "$COMMAND_LOG"
EOF

  cat > "$TEST_ROOT/fake-bin/ditto" <<'EOF'
#!/bin/zsh
set -euo pipefail
print -r -- "ditto|$*" >> "$COMMAND_LOG"
touch "${@[-1]}"
EOF

  cat > "$TEST_ROOT/fake-bin/xcrun" <<'EOF'
#!/bin/zsh
set -euo pipefail
print -r -- "xcrun|$*" >> "$COMMAND_LOG"
if [[ "$1" == "notarytool" && "$2" == "submit" ]]; then
  print -r -- "{\"id\":\"test-submission\",\"status\":\"${FAKE_NOTARY_STATUS:-Accepted}\",\"message\":\"Processing complete\"}"
fi
EOF

  cat > "$TEST_ROOT/fake-bin/plutil" <<'EOF'
#!/bin/zsh
set -euo pipefail
print -r -- "plutil|$*" >> "$COMMAND_LOG"
print -r -- "${FAKE_NOTARY_STATUS:-Accepted}"
EOF

  cat > "$TEST_ROOT/fake-bin/spctl" <<'EOF'
#!/bin/zsh
set -euo pipefail
print -r -- "spctl|$*" >> "$COMMAND_LOG"
EOF

  chmod 755 "$TEST_ROOT/fake-bin/"*
  : > "$TEST_ROOT/commands.log"
}

run_build() {
  env \
    PATH="$TEST_ROOT/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    COMMAND_LOG="$TEST_ROOT/commands.log" \
    FAKE_SWIFT_BIN="$TEST_ROOT/swift-bin" \
    "$@" \
    zsh "$TEST_ROOT/scripts/build-app.sh" > "$TEST_ROOT/stdout.log" 2> "$TEST_ROOT/stderr.log"
}

test_local_build_stays_adhoc_and_offline() {
  make_fixture
  run_build

  local command_log="$(<"$TEST_ROOT/commands.log")"
  assert_contains "$command_log" "codesign|--force --sign - $TEST_ROOT/dist/OpenCodexTray.app"
  assert_not_contains "$command_log" "notarytool"
  assert_not_contains "$command_log" "stapler"
  [[ -d "$TEST_ROOT/dist/OpenCodexTray.app" ]] || fail "local build did not create app bundle"
}

test_build_removes_stale_app_contents() {
  make_fixture
  mkdir -p "$TEST_ROOT/dist/OpenCodexTray.app/Contents/Resources"
  touch "$TEST_ROOT/dist/OpenCodexTray.app/Contents/Resources/private-stale-file"

  run_build

  [[ ! -e "$TEST_ROOT/dist/OpenCodexTray.app/Contents/Resources/private-stale-file" ]] \
    || fail "build preserved stale app contents"
}

test_release_build_requires_private_signing_configuration() {
  make_fixture

  local build_exit=0
  run_build NOTARIZE=1 SIGNING_IDENTITY= NOTARY_PROFILE= || build_exit=$?
  [[ "$build_exit" != "0" ]] || fail "release build succeeded without private signing configuration"

  local command_log="$(<"$TEST_ROOT/commands.log")"
  assert_not_contains "$command_log" "codesign|--force --options runtime"
  assert_contains "$(<"$TEST_ROOT/stderr.log")" "SIGNING_IDENTITY is required when NOTARIZE=1"
}

test_release_build_removes_stale_archive_on_early_failure() {
  make_fixture
  mkdir -p "$TEST_ROOT/dist"
  touch "$TEST_ROOT/dist/OpenCodexTray.zip"

  local build_exit=0
  run_build \
    NOTARIZE=1 \
    SIGNING_IDENTITY='Developer ID Application: Example Developer (ABCDE12345)' \
    NOTARY_PROFILE=macos-notarization \
    FAKE_SWIFT_FAIL=1 || build_exit=$?
  [[ "$build_exit" != "0" ]] || fail "release build succeeded when Swift build failed"
  [[ ! -e "$TEST_ROOT/dist/OpenCodexTray.zip" ]] || fail "early release failure left stale ZIP"
}

test_dotenv_cannot_enable_notarization() {
  make_fixture
  cat > "$TEST_ROOT/.env" <<'EOF'
NOTARIZE=1
EXPLICIT_NOTARIZE=1
SIGNING_IDENTITY='Developer ID Application: Example Developer (ABCDE12345)'
NOTARY_PROFILE='macos-notarization'
EOF

  run_build

  local command_log="$(<"$TEST_ROOT/commands.log")"
  assert_contains "$command_log" "codesign|--force --sign - $TEST_ROOT/dist/OpenCodexTray.app"
  assert_not_contains "$command_log" "notarytool"
}

test_explicit_release_environment_overrides_dotenv() {
  make_fixture
  cat > "$TEST_ROOT/.env" <<'EOF'
SIGNING_IDENTITY='Developer ID Application: Dotenv Developer (DOTENV1234)'
NOTARY_PROFILE='dotenv-notarization'
EXPLICIT_SIGNING_IDENTITY='Developer ID Application: Hijacked Developer (HIJACK1234)'
EXPLICIT_NOTARY_PROFILE='hijacked-notarization'
EOF

  run_build \
    NOTARIZE=1 \
    SIGNING_IDENTITY='Developer ID Application: Environment Developer (ENVIRON123)' \
    NOTARY_PROFILE=environment-notarization

  local command_log="$(<"$TEST_ROOT/commands.log")"
  assert_contains "$command_log" "--sign Developer ID Application: Environment Developer (ENVIRON123)"
  assert_contains "$command_log" "--keychain-profile environment-notarization"
  assert_not_contains "$command_log" "Dotenv Developer"
  assert_not_contains "$command_log" "dotenv-notarization"
  assert_not_contains "$command_log" "Hijacked Developer"
  assert_not_contains "$command_log" "hijacked-notarization"
}

test_dotenv_is_sourced_once() {
  make_fixture
  cat > "$TEST_ROOT/.env" <<'EOF'
SIGNING_IDENTITY='Developer ID Application: Example Developer (ABCDE12345)'
NOTARY_PROFILE='macos-notarization'
EOF

  run_build NOTARIZE=1

  local command_log="$(<"$TEST_ROOT/commands.log")"
  assert_contains "$command_log" "--sign Developer ID Application: Example Developer (ABCDE12345)"
  assert_contains "$command_log" "--keychain-profile macos-notarization"
}

test_dotenv_is_data_only_and_cannot_redirect_build_paths() {
  make_fixture
  local protected_file="$TEST_ROOT/must-survive"
  local side_effect_file="$TEST_ROOT/must-not-exist"
  touch "$protected_file"
  cat > "$TEST_ROOT/.env" <<EOF
APP='$protected_file'
PATH='/not/a/real/path'
touch '$side_effect_file'
SIGNING_IDENTITY='Developer ID Application: Example Developer (ABCDE12345)'
NOTARY_PROFILE='macos-notarization'
EOF

  local build_exit=0
  run_build NOTARIZE=1 || build_exit=$?

  [[ -e "$protected_file" ]] || fail ".env redirected app cleanup"
  [[ ! -e "$side_effect_file" ]] || fail ".env executed shell commands"
  [[ "$build_exit" == "0" ]] || fail ".env altered build control state"
}

test_explicit_empty_release_environment_rejects_dotenv_fallback() {
  make_fixture
  cat > "$TEST_ROOT/.env" <<'EOF'
SIGNING_IDENTITY='Developer ID Application: Dotenv Developer (DOTENV1234)'
NOTARY_PROFILE='dotenv-notarization'
EOF

  local build_exit=0
  run_build NOTARIZE=1 SIGNING_IDENTITY= NOTARY_PROFILE= || build_exit=$?
  [[ "$build_exit" != "0" ]] || fail "explicit empty release configuration fell back to .env"

  assert_contains "$(<"$TEST_ROOT/stderr.log")" "SIGNING_IDENTITY is required when NOTARIZE=1"
  assert_not_contains "$(<"$TEST_ROOT/commands.log")" "Dotenv Developer"
}

test_release_build_signs_notarizes_staples_and_repackages() {
  make_fixture
  cat > "$TEST_ROOT/.env" <<'EOF'
SIGNING_IDENTITY='Developer ID Application: Example Developer (ABCDE12345)'
NOTARY_PROFILE='macos-notarization'
EOF
  run_build NOTARIZE=1

  local command_log="$(<"$TEST_ROOT/commands.log")"
  local identity="Developer ID Application: Example Developer (ABCDE12345)"
  local app="$TEST_ROOT/dist/OpenCodexTray.app"
  local archive="$TEST_ROOT/dist/OpenCodexTray.zip"

  assert_contains "$command_log" "codesign|--force --options runtime --timestamp --sign $identity $app"
  assert_contains "$command_log" "codesign|--verify --deep --strict --verbose=4 $app"
  assert_contains "$command_log" "xcrun|notarytool submit $archive --keychain-profile macos-notarization --wait --timeout 30m --output-format json"
  assert_contains "$command_log" "xcrun|stapler staple $app"
  assert_contains "$command_log" "xcrun|stapler validate $app"
  assert_contains "$command_log" "spctl|--assess --type execute --verbose=4 $app"
  [[ -f "$archive" ]] || fail "release build did not create distributable ZIP"

  local archive_count="$(grep -c "^ditto|-c -k --sequesterRsrc --keepParent $app $archive$" "$TEST_ROOT/commands.log")"
  [[ "$archive_count" == "2" ]] || fail "expected ZIP before and after stapling; got $archive_count archive operations"

  local staple_line="$(grep -n "^xcrun|stapler staple " "$TEST_ROOT/commands.log" | cut -d: -f1)"
  local final_archive_line="$(grep -n "^ditto|-c -k --sequesterRsrc --keepParent " "$TEST_ROOT/commands.log" | tail -1 | cut -d: -f1)"
  (( final_archive_line > staple_line )) || fail "final ZIP was not created after stapling"
}

test_release_build_stops_when_notarization_is_rejected() {
  make_fixture

  local build_exit=0
  run_build \
    NOTARIZE=1 \
    SIGNING_IDENTITY='Developer ID Application: Example Developer (ABCDE12345)' \
    NOTARY_PROFILE=macos-notarization \
    FAKE_NOTARY_STATUS=Invalid || build_exit=$?
  [[ "$build_exit" != "0" ]] || fail "release build succeeded with Invalid notarization status"

  local command_log="$(<"$TEST_ROOT/commands.log")"
  assert_not_contains "$command_log" "stapler staple"
  assert_not_contains "$command_log" "spctl|"
  [[ ! -e "$TEST_ROOT/dist/OpenCodexTray.zip" ]] || fail "rejected notarization left a distributable ZIP"
}

test_local_build_stays_adhoc_and_offline
test_build_removes_stale_app_contents
test_release_build_requires_private_signing_configuration
test_release_build_removes_stale_archive_on_early_failure
test_dotenv_cannot_enable_notarization
test_explicit_release_environment_overrides_dotenv
test_dotenv_is_sourced_once
test_dotenv_is_data_only_and_cannot_redirect_build_paths
test_explicit_empty_release_environment_rejects_dotenv_fallback
test_release_build_signs_notarizes_staples_and_repackages
test_release_build_stops_when_notarization_is_rejected

print -- "PASS: build-app release tests"
