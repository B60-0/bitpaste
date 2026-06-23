#!/usr/bin/env bash
set -euo pipefail

SOURCE_APP="${1:-}"
APP_DIR="$HOME/Applications/BitPaste.app"

if [[ -z "$SOURCE_APP" ]]; then
  SOURCE_APP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/BitPaste.app"
fi

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Could not find BitPaste.app at $SOURCE_APP" >&2
  exit 1
fi

pkill -f "$APP_DIR/Contents/MacOS/bitpaste" >/dev/null 2>&1 || true

mkdir -p "$HOME/Applications"
rm -rf "$APP_DIR"
ditto "$SOURCE_APP" "$APP_DIR"
chmod +x "$APP_DIR/Contents/MacOS/bitpaste"
xattr -dr com.apple.quarantine "$APP_DIR" >/dev/null 2>&1 || true

open -gj "$APP_DIR"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true

echo "BitPaste installed."
echo "Shortcut: command+option+shift+v"
echo "App: $APP_DIR"
echo "One final macOS step: enable BitPaste.app in Privacy & Security > Accessibility."
