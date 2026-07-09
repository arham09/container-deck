#!/bin/bash
# Builds, signs, and packages ContainerDeck.dmg.
# Set DEVELOPER_ID to a "Developer ID Application: …" identity for
# distribution; unset = ad-hoc signature (local use only).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/make-app-bundle.sh" release
APP="$ROOT/.build/ContainerDeck.app"
DMG="$ROOT/.build/ContainerDeck.dmg"

if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "Signing with: $DEVELOPER_ID (hardened runtime)"
    codesign --force --deep --options runtime --sign "$DEVELOPER_ID" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
else
    echo "DEVELOPER_ID not set — keeping ad-hoc signature (local use only)"
fi

rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname ContainerDeck -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Created $DMG"
echo "Next: notarize + staple (see docs/release.md)"
