#!/usr/bin/env bash
set -euo pipefail

package_dir="${1:-dist/demo}"

python3 - "$package_dir" <<'PY'
from __future__ import annotations

import json
import hashlib
import re
import struct
import sys
from pathlib import Path

root = Path(sys.argv[1])
errors: list[str] = []


def msb2_operation_ids(path: Path) -> set[str]:
    data = path.read_bytes()
    offset = 8

    def u32() -> int:
        nonlocal offset
        if offset + 4 > len(data):
            raise ValueError("truncated u32")
        value = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        return value

    def string() -> str:
        nonlocal offset
        size = u32()
        if offset + size > len(data):
            raise ValueError("truncated string")
        raw = data[offset:offset + size]
        offset += size
        return raw.decode("utf-8")

    module_size = u32()
    offset += module_size
    if offset > len(data):
        raise ValueError("truncated executable section")
    result: set[str] = set()
    for _ in range(u32()):
        operation_id = string()
        if operation_id in result:
            raise ValueError(f"duplicate operation ID {operation_id!r}")
        result.add(operation_id)
        string()  # presentation ID
        for _ in range(u32()):
            string()
        string()  # scene
        u32()  # ordinal
    return result


def require_file(relative: str) -> Path:
    path = root / relative
    if not path.is_file():
        errors.append(f"missing required file: {relative}")
    elif path.stat().st_size == 0:
        errors.append(f"required file is empty: {relative}")
    return path


index_html = require_file("index.html")
manifest_path = require_file("manifest.json")
msb = require_file("game.msb")
require_file("host_web.wasm")

if msb.is_file() and msb.read_bytes()[:4] != b"MSB2":
    errors.append("game.msb does not start with the MSB2 magic header")

stable_operation_ids: set[str] = set()
if msb.is_file() and msb.read_bytes()[:4] == b"MSB2":
    try:
        stable_operation_ids = msb2_operation_ids(msb)
    except (OSError, UnicodeError, ValueError, struct.error) as error:
        errors.append(f"game.msb has an invalid MSB2 stable-operation section: {error}")

if manifest_path.is_file() and manifest_path.stat().st_size:
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        errors.append(f"manifest.json is not valid UTF-8 JSON: {error}")
    else:
        if manifest.get("package_schema_version") != 2:
            errors.append("manifest package_schema_version must equal 2")
        default_locale = manifest.get("default_locale")
        supported_locales = manifest.get("supported_locales")
        if not isinstance(default_locale, str) or not default_locale:
            errors.append("manifest default_locale must be a non-empty string")
        if (
            not isinstance(supported_locales, list)
            or not supported_locales
            or any(not isinstance(locale, str) or not locale for locale in supported_locales)
        ):
            errors.append(
                "manifest supported_locales must be a non-empty array of strings"
            )
        else:
            if len(set(supported_locales)) != len(supported_locales):
                errors.append("manifest supported_locales must not contain duplicates")
            if default_locale not in supported_locales:
                errors.append(
                    "manifest default_locale must appear in supported_locales"
                )
        digests = manifest.get("digests")
        declared: set[str] = set()
        if not isinstance(digests, dict) or not digests:
            errors.append("manifest digests must be a non-empty object")
            digests = {}
        for relative, expected in digests.items():
            if (
                not isinstance(relative, str)
                or not relative
                or relative.startswith("/")
                or "\\" in relative
                or any(part in ("", ".", "..") for part in relative.split("/"))
            ):
                errors.append(f"manifest digest has unsafe artifact path: {relative!r}")
                continue
            declared.add(relative)
            if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
                errors.append(f"manifest digest for {relative!r} must be lowercase SHA-256")
                continue
            artifact = require_file(relative)
            if artifact.is_file() and artifact.stat().st_size:
                actual = hashlib.sha256(artifact.read_bytes()).hexdigest()
                if actual != expected:
                    errors.append(f"digest mismatch for artifact: {relative}")
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
                if relative not in declared:
                    errors.append(f"manifest {section}.{asset_id} is missing from digests")

        compatibility = manifest.get("legacy_save_compatibility")
        if not isinstance(compatibility, dict) or compatibility.get("schema_version") != 1:
            errors.append("manifest legacy_save_compatibility schema_version must equal 1")
        else:
            entries = compatibility.get("entries")
            if not isinstance(entries, list):
                errors.append("manifest legacy_save_compatibility.entries must be an array")
            else:
                locations: set[tuple[str, int]] = set()
                for index, entry in enumerate(entries):
                    label = f"manifest legacy_save_compatibility.entries[{index}]"
                    if not isinstance(entry, dict):
                        errors.append(f"{label} must be an object")
                        continue
                    scene, ip = entry.get("scene"), entry.get("legacy_ip")
                    operation_id = entry.get("operation_id")
                    if not isinstance(scene, str) or not scene:
                        errors.append(f"{label}.scene must be a non-empty string")
                    if not isinstance(ip, int) or ip < 0:
                        errors.append(f"{label}.legacy_ip must be a non-negative integer")
                    if isinstance(scene, str) and isinstance(ip, int):
                        location = (scene, ip)
                        if location in locations:
                            errors.append(f"{label} duplicates legacy location {scene}#{ip}")
                        locations.add(location)
                    if not isinstance(operation_id, str) or operation_id not in stable_operation_ids:
                        errors.append(f"{label}.operation_id must reference an MSB2 stable operation")
                    old_choices, choice_ids = entry.get("legacy_choices"), entry.get("choice_ids")
                    if old_choices is not None or choice_ids is not None:
                        if not isinstance(old_choices, list) or not isinstance(choice_ids, list):
                            errors.append(f"{label} choice mappings must be arrays")
                        elif len(old_choices) != len(choice_ids):
                            errors.append(f"{label} choice mapping lengths must match")

        actual_artifacts = {
            path.relative_to(root).as_posix()
            for path in root.rglob("*")
            if path.is_file() and path != manifest_path
        }
        for relative in sorted(actual_artifacts - declared):
            errors.append(f"package artifact is undeclared in digests: {relative}")
        for relative in sorted(declared - actual_artifacts):
            errors.append(f"manifest digest declares missing artifact: {relative}")

if index_html.is_file() and index_html.stat().st_size:
    try:
        html = index_html.read_text(encoding="utf-8")
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
