#!/usr/bin/env bash
# Launch the built moonsight-demo dist over HTTP (WebGPU requires localhost).
# Usage:
#   ./moonsight-demo.sh            # serve dist/demo on :8080
#   PORT=9090 ./moonsight-demo.sh  # custom port
#   OPEN=1 ./moonsight-demo.sh     # also open default browser

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="${MOONSIGHT_DIST:-$ROOT/dist/demo}"
PORT="${PORT:-8080}"
HOST="${HOST:-127.0.0.1}"

if [[ ! -f "$DIST/index.html" || ! -f "$DIST/game.msb" ]]; then
  echo "error: dist not ready at $DIST" >&2
  echo "  expected index.html + game.msb" >&2
  echo "  build with:" >&2
  echo "    export CC=gcc" >&2
  echo "    cd apps/host-web && npm i && npm run build && cd ../.." >&2
  echo "    moon build --target wasm-gc --release host_web" >&2
  echo "    moon run cmd/moonsightc --target native -- build demo/game -o dist/demo" >&2
  exit 1
fi

if [[ ! -f "$DIST/host_web.wasm" ]]; then
  echo "warning: $DIST/host_web.wasm missing — rebuild host_web and re-run moonsightc build" >&2
fi

cd "$DIST"

URL="http://${HOST}:${PORT}/"
echo "MoonSight: moonsight-demo"
echo "  serving $DIST"
echo "  open    $URL"
echo "  stop    Ctrl+C"
echo

if [[ "${OPEN:-0}" == "1" ]]; then
  if command -v xdg-open >/dev/null 2>&1; then
    (sleep 0.4 && xdg-open "$URL") &
  elif command -v open >/dev/null 2>&1; then
    (sleep 0.4 && open "$URL") &
  fi
fi

# Prefer python3; fall back to python
if command -v python3 >/dev/null 2>&1; then
  exec python3 -m http.server "$PORT" --bind "$HOST"
elif command -v python >/dev/null 2>&1; then
  exec python -m http.server "$PORT" --bind "$HOST"
else
  echo "error: need python3 (or python) to serve the dist" >&2
  exit 1
fi
