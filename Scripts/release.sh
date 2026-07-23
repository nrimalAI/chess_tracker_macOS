#!/bin/bash
# Builds, signs, notarizes and packages ChessTime for public download.
#
# Requires paid Apple Developer Program enrollment: a "Developer ID Application"
# certificate in your keychain, plus a notarytool keychain profile.
#
#   xcrun notarytool store-credentials ChessTimeNotary \
#       --apple-id you@example.com --team-id ABCDE12345 --password <app-specific-password>
#
#   TEAM_ID=ABCDE12345 ./Scripts/release.sh
#
# Without enrollment you can still build and run locally — see README.md.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="${TEAM_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ChessTimeNotary}"
IDENTITY="${IDENTITY:-Developer ID Application}"
BUILD_DIR="build/release"
ARCHIVE="$BUILD_DIR/ChessTime.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/ChessTime.app"
DMG="$BUILD_DIR/ChessTime.dmg"

if [ -z "$TEAM_ID" ]; then
    echo "error: set TEAM_ID to your Apple Developer team id." >&2
    exit 1
fi

if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "error: no \"$IDENTITY\" certificate found in the keychain." >&2
    echo "       Public distribution needs paid Apple Developer Program enrollment." >&2
    exit 1
fi

echo "==> Regenerating project"
xcodegen generate

echo "==> Archiving"
rm -rf "$BUILD_DIR"
xcodebuild archive \
    -project ChessTime.xcodeproj \
    -scheme ChessTime \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime"

echo "==> Exporting"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>developer-id</string>
	<key>teamID</key><string>$TEAM_ID</string>
	<key>signingStyle</key><string>manual</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

echo "==> Building disk image"
./Scripts/package_dmg.sh "$APP" "$DMG"

echo "==> Notarizing (this can take a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Verifying Gatekeeper acceptance"
spctl -a -vvv -t install "$APP" || true

echo
echo "Done: $DMG"
