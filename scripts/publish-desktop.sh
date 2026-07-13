#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${1:-demo/game}"
OUT="${2:-dist/demo}"
# Preserve the one-shot default while allowing the release builder to reuse its
# already-built Web payload for an isolated second-stage Tauri bundle.
if test "${MOONSIGHT_SKIP_WEB_BUILD:-0}" != "1"; then
  "$ROOT/scripts/publish-web.sh" "$PROJECT" "$OUT"
fi
cd "$ROOT/host_desktop/tauri"
npm ci
TAURI_ARGS=(build)
if test -n "${MOONSIGHT_RELEASE_VERSION:-}"; then
  case "$MOONSIGHT_RELEASE_VERSION" in
    v[0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "error: invalid MOONSIGHT_RELEASE_VERSION" >&2; exit 1 ;;
  esac
  TAURI_ARGS+=(--config "{\"version\":\"${MOONSIGHT_RELEASE_VERSION#v}\"}")
fi
# linuxdeploy ships an old strip that rejects modern ELF RELR (.relr.dyn) sections
# on current Fedora/Arch toolchains; NO_STRIP avoids that hard failure.
# APPIMAGE_EXTRACT_AND_RUN avoids fuse-mount requirements for nested AppImages.
export NO_STRIP="${NO_STRIP:-true}"
export APPIMAGE_EXTRACT_AND_RUN="${APPIMAGE_EXTRACT_AND_RUN:-1}"
npm run tauri -- "${TAURI_ARGS[@]}"
