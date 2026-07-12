#!/usr/bin/env bash
set -euo pipefail

package_dir="${1:-dist/demo}"

python3 - "$package_dir" <<'PY'
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
errors: list[str] = []


def require_file(relative: str) -> Path:
    path = root / relative
    if not path.is_file():
        errors.append(f"missing required file: {relative}")
    elif path.stat().st_size == 0:
        errors.append(f"required file is empty: {relative}")
    return path


index = require_file("index.html")
manifest_path = require_file("manifest.json")
msb = require_file("game.msb")
require_file("host_web.wasm")

if msb.is_file() and msb.read_bytes()[:4] != b"MSB1":
    errors.append("game.msb does not start with the MSB1 magic header")

if manifest_path.is_file() and manifest_path.stat().st_size:
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        errors.append(f"manifest.json is not valid UTF-8 JSON: {error}")
    else:
        for section in ("resources", "audio"):
            entries = manifest.get(section, {})
            if not isinstance(entries, dict):
                errors.append(f"manifest field {section!r} must be an object")
                continue
            for asset_id, relative in entries.items():
                if not isinstance(relative, str) or not relative:
                    errors.append(
                        f"manifest {section}.{asset_id} must be a non-empty path"
                    )
                    continue
                require_file(relative)

if index.is_file() and index.stat().st_size:
    try:
        html = index.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        errors.append(f"index.html is not valid UTF-8 text: {error}")
    else:
        local_refs = re.findall(r'(?:src|href)=["\'](?:\./)?([^"\']+)["\']', html)
        if not local_refs:
            errors.append("index.html has no local script or stylesheet references")
        for relative in local_refs:
            require_file(relative.split("?", 1)[0].split("#", 1)[0])

if errors:
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    raise SystemExit(1)

print(f"OK: verified packaged distribution at {root}")
PY
