#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Ensures dist/demo exists then tauri build
"$ROOT/scripts/publish-web.sh" demo/game dist/demo
cd "$ROOT/host_desktop/tauri"
npm ci
npm run tauri build
