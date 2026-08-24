#!/bin/bash
# Builds the release binary and packages Desktop/MindFlow.app.
set -e
cd "$(dirname "$0")/.."
VERSION=${1:-3.8}
swift build -c release --product MindFlow 2>&1 | tail -1
APP=~/Desktop/MindFlow.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MindFlow "$APP/Contents/MacOS/MindFlow"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MindFlow</string>
    <key>CFBundleDisplayName</key><string>MindFlow</string>
    <key>CFBundleIdentifier</key><string>com.agenthub.mindflow</string>
    <key>CFBundleExecutable</key><string>MindFlow</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundlePackageType</key><string>APPL</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" 2>/dev/null || true
touch "$APP"
echo "Packaged $APP (v$VERSION)"
