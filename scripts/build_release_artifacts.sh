#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=""
OUT=""

usage() {
  echo "usage: $0 --version v1.0.0 --out RELEASE_DIR" >&2
}

while (($#)); do
  case "$1" in
    --version)
      test $# -ge 2 || { usage; exit 2; }
      VERSION="$2"
      shift 2
      ;;
    --out)
      test $# -ge 2 || { usage; exit 2; }
      OUT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

test -n "$VERSION" && test -n "$OUT" || { usage; exit 2; }
cd "$ROOT"
test "$(git status --porcelain)" = "" || { echo "error: dirty worktree" >&2; exit 1; }
test "$VERSION" = "v1.0.0" || { echo "error: expected v1.0.0" >&2; exit 1; }
ARCH=x86_64

OUT="$(python3 -c 'import os, sys; print(os.path.abspath(sys.argv[1]))' "$OUT")"
test ! -e "$OUT/first" || { echo "error: first build already exists: $OUT/first" >&2; exit 1; }
test ! -e "$OUT/second" || { echo "error: second build already exists: $OUT/second" >&2; exit 1; }
mkdir -p "$OUT"

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/moonsight-release.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
COMMIT="$(git rev-parse HEAD)"
SOURCE_DATE_EPOCH="$(git show -s --format=%ct HEAD)"
ATTEMPT_ID="rc-$(date -u +%Y%m%dT%H%M%SZ)-${COMMIT:0:12}"

zip_web_dist() {
  local source_dir="$1"
  local output_zip="$2"
  python3 - "$source_dir" "$output_zip" <<'PY'
import os
import stat
import sys
import zipfile
from pathlib import Path

source = Path(sys.argv[1])
output = Path(sys.argv[2])
if not source.is_dir():
    raise SystemExit(f"error: Web distribution is missing: {source}")
paths = sorted(
    (path for path in source.rglob("*") if path.is_file() or path.is_symlink()),
    key=lambda path: path.relative_to(source).as_posix(),
)
with zipfile.ZipFile(
    output,
    "w",
    compression=zipfile.ZIP_DEFLATED,
    compresslevel=9,
    strict_timestamps=True,
) as archive:
    for path in paths:
        if path.is_symlink():
            raise SystemExit(f"error: Web distribution contains a symlink: {path}")
        relative = path.relative_to(source).as_posix()
        info = zipfile.ZipInfo(relative, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.create_system = 3
        mode = 0o755 if path.stat().st_mode & stat.S_IXUSR else 0o644
        info.external_attr = (stat.S_IFREG | mode) << 16
        info.flag_bits |= 0x800
        archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
PY
}

copy_single_bundle() {
  local bundle_dir="$1"
  local pattern="$2"
  local destination="$3"
  local -a matches=()
  while IFS= read -r -d '' match; do
    matches+=("$match")
  done < <(find "$bundle_dir" -maxdepth 1 -type f -name "$pattern" -print0)
  test "${#matches[@]}" -eq 1 || {
    echo "error: expected exactly one $pattern under $bundle_dir" >&2
    exit 1
  }
  cp -- "${matches[0]}" "$destination"
}

write_metadata() {
  local artifact_dir="$1"
  local build_number="$2"
  local release_candidate="$3"
  local built_at_utc="$4"
  COMMIT="$COMMIT" VERSION="$VERSION" ARCH="$ARCH" ATTEMPT_ID="$ATTEMPT_ID" \
    SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" BUILD_NUMBER="$build_number" \
    RELEASE_CANDIDATE="$release_candidate" BUILT_AT_UTC="$built_at_utc" \
    python3 - "$artifact_dir" <<'PY'
import hashlib
import json
import os
import platform
import socket
import sys
from pathlib import Path

root = Path(sys.argv[1])
artifacts = []
for path in sorted(root.iterdir()):
    if path.name in {"SHA256SUMS", "build-metadata.json"} or not path.is_file():
        continue
    data = path.read_bytes()
    artifacts.append(
        {
            "path": path.name,
            "size_bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        }
    )
metadata = {
    "schema_version": 1,
    "attempt_id": os.environ["ATTEMPT_ID"],
    "candidate_commit": os.environ["COMMIT"],
    "version": os.environ["VERSION"],
    "architecture": os.environ["ARCH"],
    "build_number": int(os.environ["BUILD_NUMBER"]),
    "release_candidate": os.environ["RELEASE_CANDIDATE"] == "true",
    "built_at_utc": os.environ["BUILT_AT_UTC"],
    "build_host": socket.gethostname(),
    "build_platform": platform.platform(),
    "source_date_epoch": int(os.environ["SOURCE_DATE_EPOCH"]),
    "artifacts": artifacts,
}
(root / "build-metadata.json").write_text(
    json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
PY
}

build_set() {
  local build_number="$1"
  local destination="$2"
  local target_dir="$STAGING/target-$build_number"
  local artifact_dir="$STAGING/$destination"
  local web_dist="$ROOT/dist/demo"
  local built_at_utc
  mkdir -p "$artifact_dir"
  rm -rf "$web_dist" "$target_dir"

  SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" TZ=UTC LC_ALL=C \
    "$ROOT/scripts/publish-web.sh" demo/game dist/demo
  zip_web_dist "$web_dist" "$artifact_dir/moonsight-web-${ARCH}-${VERSION}.zip"

  SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" TZ=UTC LC_ALL=C \
    MOONSIGHT_SKIP_WEB_BUILD=1 MOONSIGHT_RELEASE_VERSION="$VERSION" \
    MOONSIGHT_BUILD_NUMBER="$build_number" CARGO_TARGET_DIR="$target_dir" \
    "$ROOT/scripts/publish-desktop.sh" demo/game dist/demo

  copy_single_bundle "$target_dir/release/bundle/appimage" '*.AppImage' \
    "$artifact_dir/moonsight-linux-${ARCH}-${VERSION}.AppImage"
  copy_single_bundle "$target_dir/release/bundle/deb" '*.deb' \
    "$artifact_dir/moonsight-linux-${ARCH}-${VERSION}.deb"
  copy_single_bundle "$target_dir/release/bundle/rpm" '*.rpm' \
    "$artifact_dir/moonsight-linux-${ARCH}-${VERSION}.rpm"

  built_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if test "$build_number" -eq 1; then
    (cd "$artifact_dir" && sha256sum \
      "moonsight-web-${ARCH}-${VERSION}.zip" \
      "moonsight-linux-${ARCH}-${VERSION}.AppImage" \
      "moonsight-linux-${ARCH}-${VERSION}.deb" \
      "moonsight-linux-${ARCH}-${VERSION}.rpm" > SHA256SUMS)
    write_metadata "$artifact_dir" "$build_number" true "$built_at_utc"
  else
    write_metadata "$artifact_dir" "$build_number" false "$built_at_utc"
  fi
}

build_set 1 first
build_set 2 second
mv "$STAGING/first" "$OUT/first"
mv "$STAGING/second" "$OUT/second"
echo "OK: release candidate artifacts: $OUT/first"
echo "OK: reproducibility comparison artifacts: $OUT/second"
