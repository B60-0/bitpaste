#!/usr/bin/env bash
set -euo pipefail

REPO="${BITPASTE_REPO:-B60-0/bitpaste}"
DMG_URL="${BITPASTE_DMG_URL:-https://github.com/$REPO/releases/latest/download/BitPaste.dmg}"
TMP_DIR="$(mktemp -d)"
DMG="$TMP_DIR/BitPaste.dmg"
MOUNT="$TMP_DIR/mount"

cleanup() {
  hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$MOUNT"

echo "Downloading BitPaste..."
curl -fsSL "$DMG_URL" -o "$DMG"

echo "Mounting installer..."
hdiutil attach "$DMG" -mountpoint "$MOUNT" -nobrowse -quiet

echo "Installing BitPaste..."
APP_DIR="$HOME/Applications/BitPaste.app"
pkill -f "$APP_DIR/Contents/MacOS/bitpaste" >/dev/null 2>&1 || true
mkdir -p "$HOME/Applications"
rm -rf "$APP_DIR"
ditto "$MOUNT/BitPaste.app" "$APP_DIR"
chmod +x "$APP_DIR/Contents/MacOS/bitpaste"
xattr -dr com.apple.quarantine "$APP_DIR" >/dev/null 2>&1 || true
open -gj "$APP_DIR"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true

echo "BitPaste installed."
echo "Shortcut: command+option+shift+v"
echo "App: $APP_DIR"
echo "One final macOS step: enable BitPaste.app in Privacy & Security > Accessibility."
