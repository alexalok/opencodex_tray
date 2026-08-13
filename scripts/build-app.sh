#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/dist/OpenCodexTray.app"
ARCHIVE="$ROOT/dist/OpenCodexTray.zip"

typeset -r REQUESTED_NOTARIZE="${NOTARIZE-0}"
typeset -r SIGNING_IDENTITY_WAS_SET="${+SIGNING_IDENTITY}"
typeset -r NOTARY_PROFILE_WAS_SET="${+NOTARY_PROFILE}"
typeset -r REQUESTED_SIGNING_IDENTITY="${SIGNING_IDENTITY-}"
typeset -r REQUESTED_NOTARY_PROFILE="${NOTARY_PROFILE-}"
unset NOTARIZE SIGNING_IDENTITY NOTARY_PROFILE
if [[ -f "$ROOT/.env" ]]; then
  while IFS= read -r DOTENV_LINE || [[ -n "$DOTENV_LINE" ]]; do
    case "$DOTENV_LINE" in
      SIGNING_IDENTITY=*) DOTENV_VALUE="${DOTENV_LINE#*=}" ;;
      NOTARY_PROFILE=*) DOTENV_VALUE="${DOTENV_LINE#*=}" ;;
      *) continue ;;
    esac

    if [[ "$DOTENV_VALUE" == \'*\' ]]; then
      DOTENV_VALUE="${DOTENV_VALUE#\'}"
      DOTENV_VALUE="${DOTENV_VALUE%\'}"
    fi

    case "$DOTENV_LINE" in
      SIGNING_IDENTITY=*) SIGNING_IDENTITY="$DOTENV_VALUE" ;;
      NOTARY_PROFILE=*) NOTARY_PROFILE="$DOTENV_VALUE" ;;
    esac
  done < "$ROOT/.env"
fi
typeset -r DOTENV_SIGNING_IDENTITY="${SIGNING_IDENTITY-}"
typeset -r DOTENV_NOTARY_PROFILE="${NOTARY_PROFILE-}"
NOTARIZE="$REQUESTED_NOTARIZE"
if [[ "$SIGNING_IDENTITY_WAS_SET" == "1" ]]; then
  SIGNING_IDENTITY="$REQUESTED_SIGNING_IDENTITY"
else
  SIGNING_IDENTITY="$DOTENV_SIGNING_IDENTITY"
fi
if [[ "$NOTARY_PROFILE_WAS_SET" == "1" ]]; then
  NOTARY_PROFILE="$REQUESTED_NOTARY_PROFILE"
else
  NOTARY_PROFILE="$DOTENV_NOTARY_PROFILE"
fi
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ "$NOTARIZE" == "1" ]]; then
  ARCHIVE_COMPLETE=0
  cleanup_incomplete_archive() {
    [[ "$ARCHIVE_COMPLETE" == "1" ]] || rm -f "$ARCHIVE"
  }
  trap cleanup_incomplete_archive EXIT
  rm -f "$ARCHIVE"

  : "${SIGNING_IDENTITY:?SIGNING_IDENTITY is required when NOTARIZE=1}"
  : "${NOTARY_PROFILE:?NOTARY_PROFILE is required when NOTARIZE=1}"
fi

rm -rf "$APP"
swift build --package-path "$ROOT" -c release --product OpenCodexTray
BIN_DIR="$(swift build --package-path "$ROOT" -c release --show-bin-path)"

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
if [[ "$NOTARIZE" == "1" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=4 "$APP"

  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"

  NOTARY_RESULT="$(xcrun notarytool submit "$ARCHIVE" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --timeout 30m \
    --output-format json)"
  NOTARY_STATUS="$(print -r -- "$NOTARY_RESULT" | plutil -extract status raw -o - -)"
  if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
    print -u2 -r -- "$NOTARY_RESULT"
    print -u2 -- "Notarization failed with status: $NOTARY_STATUS"
    exit 1
  fi

  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"

  rm -f "$ARCHIVE"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
  spctl --assess --type execute --verbose=4 "$APP"
  ARCHIVE_COMPLETE=1

  print -- "$ARCHIVE"
else
  codesign --force --sign - "$APP"
fi

echo "$APP"
