#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.1}"
DIST="$ROOT/dist"
STAGE="$DIST/dmg-stage"
VOLNAME="BitPaste"
DMG="$DIST/BitPaste.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE" "$DIST"

BITPASTE_VERSION="$VERSION" "$ROOT/scripts/build-app.sh" "$STAGE/BitPaste.app" >/dev/null
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/README.txt" <<'README'
BitPaste

Drag BitPaste.app into Applications, then open BitPaste once.

macOS will ask for Accessibility permission. Enable BitPaste.app there.

Shortcut: command+option+shift+v
README

hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

echo "$DMG"
