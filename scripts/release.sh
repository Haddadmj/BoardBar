#!/usr/bin/env bash
# Builds, signs, notarizes, and packages BoardBar into a distributable DMG.
#
# BoardBar is an Xcode target, not a SwiftPM executable, so this archives and
# exports rather than assembling a bundle by hand. The .xcodeproj is generated,
# so the script regenerates it first — see project.yml.
#
# For a fully shippable build you need an Apple Developer account:
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"  # signing identity
#   AC_KEYCHAIN_PROFILE="notary"                                 # notarytool profile
#     (create once: xcrun notarytool store-credentials notary \
#        --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>)
#
# AC_KEYCHAIN_PROFILE defaults to "notary". A build that is not notarized will
# not open on anyone else's Mac, so skipping it takes SKIP_NOTARIZE=1 rather than
# being what happens when a variable is unset.
#
# Unlike the other apps here there is no unsigned fallback. BoardBar is
# sandboxed and carries an App Group, which needs a real provisioning profile —
# an ad-hoc signature cannot produce a bundle that runs anywhere else.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="BoardBar"
TEAM_ID="${TEAM_ID:-7DA454D7FF}"
BUILD="$ROOT/.build"
ARCHIVE="$BUILD/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD/export"
DIST="$BUILD/dist"
DMG="$DIST/$APP_NAME.dmg"
APP="$EXPORT_DIR/$APP_NAME.app"
AC_KEYCHAIN_PROFILE="${AC_KEYCHAIN_PROFILE:-notary}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-}"

if [ -z "${DEVELOPER_ID:-}" ]; then
  echo "error: DEVELOPER_ID is not set." >&2
  echo "       BoardBar's App Group entitlement needs a real signing identity;" >&2
  echo "       there is no useful ad-hoc build. See the header of this script." >&2
  exit 1
fi

command -v xcodegen >/dev/null || {
  echo "error: xcodegen not found — brew install xcodegen" >&2; exit 1
}
command -v create-dmg >/dev/null || {
  echo "error: create-dmg not found — brew install create-dmg" >&2; exit 1
}

# Checked now rather than after the build it would otherwise waste.
if [ -z "$SKIP_NOTARIZE" ] &&
  ! xcrun notarytool history --keychain-profile "$AC_KEYCHAIN_PROFILE" >/dev/null 2>&1; then
  echo "error: notarytool profile \"$AC_KEYCHAIN_PROFILE\" is not usable." >&2
  echo "       See the header of this script, or set SKIP_NOTARIZE=1." >&2
  exit 1
fi

# Submits, waits, and fails with Apple's reasons. Without the log a rejection
# surfaces later as stapler's "Record not found", which explains nothing.
notarize() {
  local file="$1" result id status
  result="$(xcrun notarytool submit "$file" --keychain-profile "$AC_KEYCHAIN_PROFILE" \
    --wait --output-format json)" || {
    echo "error: notarytool could not submit $file" >&2
    return 1
  }
  id="$(plutil -extract id raw -o - - <<<"$result")"
  status="$(plutil -extract status raw -o - - <<<"$result")"
  echo "   $status ($id)"
  if [ "$status" != "Accepted" ]; then
    xcrun notarytool log "$id" --keychain-profile "$AC_KEYCHAIN_PROFILE" >&2 || true
    return 1
  fi
}

echo "==> Generating the Xcode project…"
(cd "$ROOT" && xcodegen generate)

echo "==> Archiving…"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild archive \
  -project "$ROOT/$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID"

# Written here rather than committed: it is derived from TEAM_ID and would be a
# third place to update when that changes.
PLIST="$BUILD/ExportOptions.plist"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST_EOF

echo "==> Exporting a Developer ID build…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$PLIST" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates

codesign --verify --strict --verbose=2 "$APP"

# Notarization happens twice, and the order is the point. The app is notarized
# and stapled BEFORE it is packaged, so the copy that ships inside the DMG
# carries its own ticket — a staple applied afterwards lands on the export
# directory, which nobody installs, and leaves the shipped app needing Apple
# online at first launch. The DMG is then signed and notarized in its own
# right, so `spctl -a -t open` accepts the file people actually download.
if [ -z "$SKIP_NOTARIZE" ]; then
  echo "==> Notarizing the app (this can take a few minutes)…"
  ZIP="$BUILD/$APP_NAME.zip"
  rm -f "$ZIP"
  # ditto, not zip: it preserves the bundle's symlinks and extended attributes.
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarize "$ZIP"
  rm -f "$ZIP"
  echo "==> Stapling the app…"
  xcrun stapler staple "$APP"
fi

echo "==> Building DMG…"
rm -rf "$DIST"; mkdir -p "$DIST"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
# ditto, for the same reason as above.
ditto "$APP" "$STAGE/$APP_NAME.app"
# The positions are the picture's: see Tools/make-dmg-background.swift. This asks
# Finder to arrange the window, so it needs a logged-in session and permission to
# automate Finder, and macOS will ask for that the first time.
create-dmg \
  --volname "$APP_NAME" \
  --background "$ROOT/Tools/dmg-background.tiff" \
  --window-pos 200 120 \
  --window-size 640 400 \
  --icon-size 128 \
  --text-size 13 \
  --icon "$APP_NAME.app" 160 180 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 480 180 \
  --no-internet-enable \
  --hdiutil-quiet \
  "$DMG" "$STAGE" >/dev/null
echo "   Wrote $DMG"

echo "==> Signing the DMG…"
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"

if [ -n "$SKIP_NOTARIZE" ]; then
  echo "==> Skipping notarization (SKIP_NOTARIZE is set). This DMG will not open elsewhere."
  echo "==> Done: $DMG"
  exit 0
fi

echo "==> Notarizing the DMG (this can take a few minutes)…"
notarize "$DMG"
echo "==> Stapling the DMG…"
xcrun stapler staple "$DMG"

# Checks the file people download, and the app inside it, the way Gatekeeper
# will. Everything above passing does not prove the staple reached the copy that
# ships, which is the mistake the ordering comment above is about.
echo "==> Verifying what ships…"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG"
MOUNT="$(mktemp -d)"
hdiutil attach "$DMG" -readonly -nobrowse -quiet -mountpoint "$MOUNT"
trap 'hdiutil detach "$MOUNT" -quiet || true; rm -rf "$STAGE" "$MOUNT"' EXIT
# Finder's layout lives in these two files. Missing, the DMG still opens and still
# installs, as a plain window with no arrow, so nothing else here would notice.
[ -f "$MOUNT/.DS_Store" ] && [ -f "$MOUNT/.background/dmg-background.tiff" ] || {
  echo "error: the DMG lost its window layout." >&2
  exit 1
}
xcrun stapler validate "$MOUNT/$APP_NAME.app"
spctl -a -t exec -vv "$MOUNT/$APP_NAME.app"
codesign --verify --deep --strict "$MOUNT/$APP_NAME.app"
if codesign -d --entitlements - "$MOUNT/$APP_NAME.app" 2>/dev/null | grep -q get-task-allow; then
  echo "error: the shipped app carries get-task-allow, which is a debug build." >&2
  exit 1
fi
echo "==> Notarized, stapled and verified ✓"

echo "==> Done: $DMG"
