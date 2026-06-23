#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.0}"
DIST="$ROOT/dist"
STAGE="$DIST/dmg-stage"
VOLNAME="BitPaste"
DMG="$DIST/BitPaste.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE" "$DIST"

BITPASTE_VERSION="$VERSION" "$ROOT/scripts/build-app.sh" "$STAGE/BitPaste.app" >/dev/null
cp "$ROOT/scripts/install-bundled-app.sh" "$STAGE/install-bundled-app.sh"

cat > "$STAGE/Install BitPaste.command" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
bash "$HERE/install-bundled-app.sh" "$HERE/BitPaste.app"
SCRIPT

cat > "$STAGE/README.txt" <<'README'
BitPaste

Run "Install BitPaste.command" to install.

After install, macOS will open Accessibility settings. Enable BitPaste.app there.

Shortcut: command+option+shift+v
README

chmod +x "$STAGE/Install BitPaste.command" "$STAGE/install-bundled-app.sh"

hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

echo "$DMG"
