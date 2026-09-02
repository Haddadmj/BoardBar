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

if [ -z "${DEVELOPER_ID:-}" ]; then
  echo "error: DEVELOPER_ID is not set." >&2
  echo "       BoardBar's App Group entitlement needs a real signing identity;" >&2
  echo "       there is no useful ad-hoc build. See the header of this script." >&2
  exit 1
fi

command -v xcodegen >/dev/null || {
  echo "error: xcodegen not found — brew install xcodegen" >&2; exit 1
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
if [ -n "${AC_KEYCHAIN_PROFILE:-}" ]; then
  echo "==> Notarizing the app (this can take a few minutes)…"
  ZIP="$BUILD/$APP_NAME.zip"
  rm -f "$ZIP"
  # ditto, not zip: it preserves the bundle's symlinks and extended attributes.
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$AC_KEYCHAIN_PROFILE" --wait
  rm -f "$ZIP"
  echo "==> Stapling the app…"
  xcrun stapler staple "$APP"
fi

echo "==> Building DMG…"
rm -rf "$DIST"; mkdir -p "$DIST"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "   Wrote $DMG"

echo "==> Signing the DMG…"
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"

if [ -n "${AC_KEYCHAIN_PROFILE:-}" ]; then
  echo "==> Notarizing the DMG (this can take a few minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$AC_KEYCHAIN_PROFILE" --wait
  echo "==> Stapling the DMG…"
  xcrun stapler staple "$DMG"
  echo "==> Notarized & stapled ✓"
else
  echo "==> Skipping notarization (set AC_KEYCHAIN_PROFILE to enable)."
fi

echo "==> Done: $DMG"
