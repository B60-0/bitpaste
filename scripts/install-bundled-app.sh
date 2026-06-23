#!/usr/bin/env bash
set -euo pipefail

LABEL="app.bitpaste"
SOURCE_APP="${1:-}"
APP_DIR="$HOME/Applications/BitPaste.app"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST="$LAUNCH_AGENTS/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/BitPaste"
CONFIG_DIR="$HOME/.config/bitpaste"
CONFIG="$CONFIG_DIR/config.json"

if [[ -z "$SOURCE_APP" ]]; then
  SOURCE_APP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/BitPaste.app"
fi

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Could not find BitPaste.app at $SOURCE_APP" >&2
  exit 1
fi

launchctl bootout "gui/$UID" "$PLIST" >/dev/null 2>&1 || true
pkill -f "$APP_DIR/Contents/MacOS/bitpaste" >/dev/null 2>&1 || true

mkdir -p "$HOME/Applications" "$LAUNCH_AGENTS" "$LOG_DIR" "$CONFIG_DIR"
rm -rf "$APP_DIR"
ditto "$SOURCE_APP" "$APP_DIR"
chmod +x "$APP_DIR/Contents/MacOS/bitpaste"
xattr -dr com.apple.quarantine "$APP_DIR" >/dev/null 2>&1 || true

if [[ ! -f "$CONFIG" ]]; then
  cat > "$CONFIG" <<CONFIG
{
  "chunkSize": 1200,
  "delayMs": 75,
  "initialDelayMs": 120,
  "waitForShortcutReleaseMs": 1000,
  "hotkey": "command+option+shift+v",
  "restoreClipboard": true
}
CONFIG
fi

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-gj</string>
    <string>$APP_DIR</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/bitpaste.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/bitpaste.err.log</string>
  <key>ProcessType</key>
  <string>Interactive</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$UID" "$PLIST"
launchctl kickstart -k "gui/$UID/$LABEL"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true

echo "BitPaste installed."
echo "Shortcut: command+option+shift+v"
echo "App: $APP_DIR"
echo "Config: $CONFIG"
echo "One final macOS step: enable BitPaste.app in Privacy & Security > Accessibility."
