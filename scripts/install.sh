#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/dist/BitPaste.app"

"$ROOT/scripts/build-app.sh" "$APP_DIR" >/dev/null
"$ROOT/scripts/install-bundled-app.sh" "$APP_DIR"
