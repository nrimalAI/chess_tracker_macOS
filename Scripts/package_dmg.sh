#!/bin/bash
# Packages a built ChessTime.app into a drag-to-Applications disk image.
#   ./Scripts/package_dmg.sh <path/to/ChessTime.app> <output.dmg>
set -euo pipefail

APP="${1:?usage: package_dmg.sh <app> <output.dmg>}"
DMG="${2:?usage: package_dmg.sh <app> <output.dmg>}"

if [ ! -d "$APP" ]; then
    echo "error: no app bundle at $APP" >&2
    exit 1
fi

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
# The Applications symlink is what makes the window a drag-and-drop installer.
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create \
    -volname ChessTime \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG"

echo "packaged $DMG"
