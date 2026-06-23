#!/usr/bin/env bash
set -euo pipefail

LABEL="app.bitpaste"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$HOME/Applications/BitPaste.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
BIN="$MACOS/bitpaste"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST="$LAUNCH_AGENTS/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/BitPaste"
CONFIG_DIR="$HOME/.config/bitpaste"
CONFIG="$CONFIG_DIR/config.json"

cd "$ROOT"
swift build -c release

launchctl bootout "gui/$UID" "$PLIST" >/dev/null 2>&1 || true
pkill -f "$BIN" >/dev/null 2>&1 || true

mkdir -p "$MACOS" "$LAUNCH_AGENTS" "$LOG_DIR" "$CONFIG_DIR"
cp "$ROOT/.build/release/bitpaste" "$BIN"
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
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS/Info.plist" >/dev/null
codesign --force --deep --sign - "$APP_DIR" >/dev/null

if [[ ! -f "$CONFIG" ]]; then
  cp "$ROOT/config.example.json" "$CONFIG"
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

echo "BitPaste installed and started."
echo "Hotkey: command+option+shift+v"
echo "App: $APP_DIR"
echo "Config: $CONFIG"
echo "Logs: $LOG_DIR"
echo "If paste events do not fire, enable Accessibility for BitPaste.app in System Settings > Privacy & Security > Accessibility."
