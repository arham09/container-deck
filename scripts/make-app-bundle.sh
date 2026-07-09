#!/bin/bash
# Builds ContainerDeck and assembles a launchable .app bundle.
# Needed because this project builds with SwiftPM (no Xcode project);
# SwiftPM produces a bare executable, and macOS app behaviors (proper
# activation, dialogs, defaults domain) want a real bundle.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP_NAME="ContainerDeck"
BUNDLE_ID="dev.containerdeck.ContainerDeck"

echo "Building ($CONFIG)..."
swift build --package-path "$ROOT" -c "$CONFIG"

BIN="$ROOT/.build/$CONFIG/$APP_NAME"
if [ ! -x "$BIN" ]; then
    echo "Built binary not found at $BIN" >&2
    exit 1
fi

APP_DIR="$ROOT/.build/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

VERSION="1.0.1"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>ContainerDeck</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>ContainerDeck opens your preferred terminal to run container shell commands.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so the bundle launches cleanly on the local machine.
# Phase 7 replaces this with Developer ID signing + notarization.
codesign --force --sign - "$APP_DIR"

echo "Created $APP_DIR"
echo "Launch with: open \"$APP_DIR\""
