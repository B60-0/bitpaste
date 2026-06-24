#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
MOUNT="$TMP_DIR/mount"
DMG="$ROOT/dist/BitPaste.dmg"

cleanup() {
  if [[ -d "$MOUNT" ]]; then
    hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || hdiutil detach "$MOUNT" -force -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

assert_file() {
  [[ -f "$1" ]] || {
    echo "missing file: $1" >&2
    exit 1
  }
}

assert_dir() {
  [[ -d "$1" ]] || {
    echo "missing directory: $1" >&2
    exit 1
  }
}

assert_executable() {
  [[ -x "$1" ]] || {
    echo "not executable: $1" >&2
    exit 1
  }
}

assert_symlink() {
  [[ -L "$1" ]] || {
    echo "missing symlink: $1" >&2
    exit 1
  }
}

echo "== Build CLI =="
swift build -c release >/dev/null
".build/release/bitpaste" --config "$TMP_DIR/no-config.json" --print-config | grep -F '"hotkey" : "command+option+shift+v"' >/dev/null
".build/release/bitpaste" --help | grep -F 'command+option+shift+v' >/dev/null

echo "== Build DMG =="
"$ROOT/scripts/package-dmg.sh" >/dev/null
assert_file "$DMG"

echo "== Inspect DMG =="
mkdir -p "$MOUNT"
hdiutil attach "$DMG" -mountpoint "$MOUNT" -nobrowse -readonly -quiet
assert_dir "$MOUNT/BitPaste.app"
assert_dir "$MOUNT/BitPaste.app/Contents"
assert_symlink "$MOUNT/Applications"
assert_file "$MOUNT/README.txt"
assert_executable "$MOUNT/BitPaste.app/Contents/MacOS/bitpaste"
assert_file "$MOUNT/BitPaste.app/Contents/Resources/BitPaste.icns"
assert_file "$MOUNT/BitPaste.app/Contents/Resources/bitpaste-logo.svg"

plutil -extract CFBundleIdentifier raw "$MOUNT/BitPaste.app/Contents/Info.plist" | grep -E '^app\.bitpaste$' >/dev/null
plutil -extract CFBundleShortVersionString raw "$MOUNT/BitPaste.app/Contents/Info.plist" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' >/dev/null
plutil -extract CFBundleIconFile raw "$MOUNT/BitPaste.app/Contents/Info.plist" | grep -E '^BitPaste$' >/dev/null
plutil -extract LSUIElement raw "$MOUNT/BitPaste.app/Contents/Info.plist" | grep -E '^true$' >/dev/null
"$MOUNT/BitPaste.app/Contents/MacOS/bitpaste" --config "$TMP_DIR/no-config.json" --print-config | grep -F '"hotkey" : "command+option+shift+v"' >/dev/null

echo "== Scan tracked files =="
privacy_patterns=(
  "/Use""rs/"
  "innovation""-2"
  "Docu""ments"
  "com[.]cod""ex"
  "app[.]cod""ex"
  "gh""o_"
  "Library/Application Support/""BitPaste"
)
privacy_pattern="$(IFS='|'; echo "${privacy_patterns[*]}")"
git -C "$ROOT" ls-files -z | xargs -0 grep -nE "$privacy_pattern" && {
  echo "tracked-file privacy scan failed" >&2
  exit 1
} || true

if [[ "${BITPASTE_VALIDATE_RELEASE:-0}" == "1" ]]; then
  echo "== Inspect latest GitHub release DMG =="
  RELEASE_TMP="$TMP_DIR/release"
  RELEASE_MOUNT="$TMP_DIR/release-mount"
  mkdir -p "$RELEASE_TMP" "$RELEASE_MOUNT"
  curl -fsSL https://github.com/B60-0/bitpaste/releases/latest/download/BitPaste.dmg -o "$RELEASE_TMP/BitPaste.dmg"
  hdiutil attach "$RELEASE_TMP/BitPaste.dmg" -mountpoint "$RELEASE_MOUNT" -nobrowse -readonly -quiet
  assert_dir "$RELEASE_MOUNT/BitPaste.app"
  assert_symlink "$RELEASE_MOUNT/Applications"
  assert_executable "$RELEASE_MOUNT/BitPaste.app/Contents/MacOS/bitpaste"
  plutil -extract CFBundleIdentifier raw "$RELEASE_MOUNT/BitPaste.app/Contents/Info.plist" | grep -E '^app\.bitpaste$' >/dev/null
  hdiutil detach "$RELEASE_MOUNT" -quiet >/dev/null 2>&1 || hdiutil detach "$RELEASE_MOUNT" -force -quiet >/dev/null 2>&1 || true
fi

echo "Validation passed."
