#!/bin/bash
# Builds the release binary and packages Bough.app.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:-3.8}
swift build -c release --product Bough 2>&1 | tail -1
swift build -c release --product MindFlowIconGen 2>&1 | tail -1
APP="${MINDFLOW_PACKAGE_APP:-$HOME/Desktop/Bough.app}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Bough "$APP/Contents/MacOS/Bough"
.build/release/MindFlowIconGen "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Bough</string>
    <key>CFBundleDisplayName</key><string>Bough</string>
    <key>CFBundleIdentifier</key><string>com.agenthub.bough</string>
    <key>CFBundleExecutable</key><string>Bough</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Bough Document</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Owner</string>
            <key>LSItemContentTypes</key>
            <array><string>com.agenthub.mindmap</string></array>
            <key>CFBundleTypeExtensions</key>
            <array><string>mindmap</string></array>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>com.agenthub.mindmap</string>
            <key>UTTypeDescription</key><string>Bough Document</string>
            <key>UTTypeConformsTo</key><array><string>public.json</string></array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key><array><string>mindmap</string></array>
            </dict>
        </dict>
    </array>
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
