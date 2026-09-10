#!/bin/bash
# Builds Bough.app and wraps it in a shareable DMG on the Desktop.
set -e
cd "$(dirname "$0")/.."
VERSION=${1:-dev}
bash scripts/package.sh "$VERSION"
STAGING=/tmp/Bough-dmg
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R ~/Desktop/Bough.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Bough" -srcfolder "$STAGING" -ov -format UDZO ~/Desktop/Bough-$VERSION.dmg
echo "DMG created: ~/Desktop/Bough-$VERSION.dmg"