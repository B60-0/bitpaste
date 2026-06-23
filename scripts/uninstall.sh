#!/usr/bin/env bash
set -euo pipefail

LABEL="app.bitpaste"
APP_DIR="$HOME/Applications/BitPaste.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$UID" "$PLIST" >/dev/null 2>&1 || true
pkill -f "$APP_DIR/Contents/MacOS/bitpaste" >/dev/null 2>&1 || true
rm -f "$PLIST"
rm -rf "$APP_DIR"

echo "BitPaste stopped and removed."
echo "Config was left at ~/.config/bitpaste/config.json"
