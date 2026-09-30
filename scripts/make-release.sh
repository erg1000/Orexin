#!/bin/zsh
# Builds a universal Orexin.app for distribution outside the App Store and packages it
# as build/Orexin-<version>.dmg.
#
# The app is ad-hoc signed (no Developer ID), so it isn't notarized: on first launch,
# macOS asks the user to allow it in System Settings → Privacy & Security.

set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_DIR=build
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP="$DERIVED_DATA/Build/Products/Release/Orexin.app"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "Building…"
xcodebuild -project Orexin.xcodeproj -scheme Orexin -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    build -quiet

# Re-sign with only the sandbox entitlement: a plain build would also include
# get-task-allow, which allows debugging and shouldn't ship.
ENTITLEMENTS="$BUILD_DIR/Orexin.entitlements"
cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
</dict>
</plist>
PLIST
codesign --force --sign - --options runtime --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$BUILD_DIR/Orexin-$VERSION.dmg"

echo "Packaging $DMG…"
STAGING="$BUILD_DIR/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Orexin" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" -quiet
rm -rf "$STAGING"

echo "Done: $DMG"
