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
bash "$MOUNT/Install BitPaste.command"
