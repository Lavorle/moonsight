#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${1:-demo/game}"
OUT="${2:-dist/demo}"
export CC="${CC:-gcc}"
export TZ="${TZ:-UTC}"
export LC_ALL="${LC_ALL:-C}"
cd "$ROOT"
cd apps/host-web && npm ci && npm run build && cd "$ROOT"
moon build --target wasm-gc --release host_web
moon run cmd/moonsightc --target native -- build "$PROJECT" -o "$OUT"
echo "OK: $OUT — serve with: cd $OUT && python3 -m http.server 8080"
