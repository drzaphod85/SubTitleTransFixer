#!/usr/bin/env bash
# Bygger Undertextaren.app i ./build (kräver Xcode 15+ / Swift 5.9+ på macOS 14+).
set -euo pipefail
cd "$(dirname "$0")"

# SwiftUI-makron (t.ex. @State) följer bara med fullständiga Xcode,
# inte med Command Line Tools.
DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEV_DIR" != *".app/Contents/Developer"* ]]; then
    XCODE="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1 || true)"
    if [[ -n "$XCODE" ]]; then
        echo "→ Bygger med $XCODE (xcode-select pekar på $DEV_DIR)"
        export DEVELOPER_DIR="$XCODE/Contents/Developer"
    else
        echo "✗ Xcode hittades inte. Command Line Tools räcker inte för SwiftUI-appar."
        echo "  Installera Xcode från App Store, öppna det en gång och kör skriptet igen."
        exit 1
    fi
fi

swift build -c release

APP="build/Undertextaren.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/Undertextaren" "$APP/Contents/MacOS/Undertextaren"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Undertextaren</string>
    <key>CFBundleDisplayName</key><string>Undertextaren</string>
    <key>CFBundleIdentifier</key><string>se.undertextaren.app</string>
    <key>CFBundleExecutable</key><string>Undertextaren</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDevelopmentRegion</key><string>sv</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>SubRip-undertext</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>CFBundleTypeExtensions</key><array><string>srt</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Ad hoc-signering så att appen kan startas lokalt och använda nyckelringen
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "✓ Klar: $APP"
echo "  Starta med: open \"$APP\""
