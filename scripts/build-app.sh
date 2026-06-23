#!/usr/bin/env bash
set -euo pipefail

LABEL="app.bitpaste"
VERSION="${BITPASTE_VERSION:-0.1.0}"
BUILD="${BITPASTE_BUILD:-1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${1:-$ROOT/dist/BitPaste.app}"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BIN="$MACOS/bitpaste"

cd "$ROOT"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT/.build/release/bitpaste" "$BIN"
cp "$ROOT/assets/bitpaste-logo.svg" "$RESOURCES/bitpaste-logo.svg"
chmod +x "$BIN"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>bitpaste</string>
  <key>CFBundleIdentifier</key>
  <string>$LABEL</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>BitPaste</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS/Info.plist" >/dev/null
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "$APP_DIR"
