#!/bin/bash
# Builds MindFlow.app and wraps it in a shareable DMG on the Desktop.
set -e
cd "$(dirname "$0")/.."
VERSION=${1:-dev}
bash scripts/package.sh "$VERSION"
STAGING=/tmp/MindFlow-dmg
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R ~/Desktop/MindFlow.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "MindFlow" -srcfolder "$STAGING" -ov -format UDZO ~/Desktop/MindFlow-$VERSION.dmg
echo "DMG created: ~/Desktop/MindFlow-$VERSION.dmg"