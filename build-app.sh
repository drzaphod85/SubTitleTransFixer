#!/usr/bin/env bash
# Builds "SubTitle TransFixer.app" in ./build (requires Xcode 15+ / Swift 5.9+ on macOS 14+).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SubTitle TransFixer"
EXECUTABLE="SubTitleTransFixer"
BUNDLE_ID="se.subtitletransfixer.app"
LANGUAGES=(en sv nb da fi is)

# Version: $VERSION, else the latest tag (v1.2.3 → 1.2.3), else 1.0.0.
if [[ -z "${VERSION:-}" ]]; then
    VERSION="$(git describe --tags --abbrev=0 2>/dev/null || true)"
    VERSION="${VERSION#v}"
    VERSION="${VERSION:-1.0.0}"
fi
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

# SwiftUI macros (e.g. @State) only ship with the full Xcode, not with the
# Command Line Tools.
DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEV_DIR" != *".app/Contents/Developer"* ]]; then
    XCODE="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1 || true)"
    if [[ -n "$XCODE" ]]; then
        echo "→ Building with $XCODE (xcode-select points to $DEV_DIR)"
        export DEVELOPER_DIR="$XCODE/Contents/Developer"
    else
        echo "✗ Xcode was not found. The Command Line Tools are not enough for SwiftUI apps."
        echo "  Install Xcode from the App Store, open it once and run this script again."
        exit 1
    fi
fi

# UNIVERSAL=1 builds one binary for both Apple silicon and Intel Macs (used for releases).
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BINARY=".build/apple/Products/Release/$EXECUTABLE"
else
    swift build -c release
    BINARY=".build/release/$EXECUTABLE"
fi
echo "→ $APP_NAME $VERSION ($BUILD_NUMBER)"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE"
cp "Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Empty .lproj folders tell macOS which languages the app supports, so that
# system panels (Open/Save) follow the app's language.
LOCALIZATIONS=""
for lang in "${LANGUAGES[@]}"; do
    mkdir -p "$APP/Contents/Resources/$lang.lproj"
    printf '"CFBundleDisplayName" = "%s";\n"CFBundleName" = "%s";\n' "$APP_NAME" "$APP_NAME" \
        > "$APP/Contents/Resources/$lang.lproj/InfoPlist.strings"
    LOCALIZATIONS+="        <string>$lang</string>"$'\n'
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
$LOCALIZATIONS    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>SubRip subtitles</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Default</string>
            <key>CFBundleTypeExtensions</key><array><string>srt</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Make Finder/Dock reload the icon
touch "$APP"

# Code signing. A "Developer ID Application" certificate (paid Apple Developer
# Program) signs for distribution: hardened runtime and a secure timestamp, as
# notarization requires. An "Apple Development" certificate keeps the app's
# identity stable between builds on your own Mac, so the keychain keeps
# releasing the API key. Without either the app is signed ad hoc.
# Pick a certificate yourself with: SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./build-app.sh
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    for kind in "Developer ID Application" "Apple Development" "Mac Developer"; do
        IDENTITY="$(printf '%s\n' "$IDENTITIES" | grep -F "\"$kind" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
        [[ -n "$IDENTITY" ]] && break
    done
fi
if [[ "$IDENTITY" == "Developer ID Application"* ]]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
    echo "✓ Signed for distribution with: $IDENTITY"
elif [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" "$APP"
    echo "✓ Signed with: $IDENTITY"
else
    codesign --force --sign - "$APP" >/dev/null 2>&1 || true
    echo "⚠ No developer certificate found – the app was signed ad hoc."
    echo "  The keychain may then forget the API key on the next build. See README → The API key."
fi

echo "✓ Done: $APP"
echo "  Start it with: open \"$APP\""
