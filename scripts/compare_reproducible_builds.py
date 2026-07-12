#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import stat
import sys
from pathlib import Path
from typing import Any


CORE_GLOBS = (
    "*.msb", "**/*.msb", "*.msb2", "**/*.msb2",
    "*.catalog", "**/*.catalog", "*.catalog.json", "**/*.catalog.json",
    "manifest.json", "**/manifest.json", "*.wasm", "**/*.wasm",
    "*.exe", "**/*.exe", "*.dll", "**/*.dll", "*.so", "**/*.so",
    "*.dylib", "**/*.dylib",
    "*.png", "**/*.png", "*.jpg", "**/*.jpg", "*.jpeg", "**/*.jpeg",
    "*.webp", "**/*.webp", "*.svg", "**/*.svg", "*.ogg", "**/*.ogg",
    "*.mp3", "**/*.mp3", "*.wav", "**/*.wav", "*.flac", "**/*.flac",
    "*.ttf", "**/*.ttf", "*.otf", "**/*.otf", "*.woff", "**/*.woff",
    "*.woff2", "**/*.woff2",
)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def files(root: Path) -> dict[str, Path]:
    return {
        path.relative_to(root).as_posix(): path
        for path in root.rglob("*")
        if path.is_file() or path.is_symlink()
    }


def raw_bytes(path: Path) -> bytes:
    if path.is_symlink():
        return ("symlink:" + os.readlink(path)).encode("utf-8")
    return path.read_bytes()


def core(path: str) -> bool:
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in CORE_GLOBS)


def validate_allowlist(data: Any) -> tuple[list[dict[str, Any]], list[str]]:
    errors: list[str] = []
    if not isinstance(data, dict) or data.get("schema_version") != 1:
        return [], ["normalization allowlist schema_version must be 1"]
    entries = data.get("entries")
    if not isinstance(entries, list):
        return [], ["normalization allowlist entries must be an array"]
    ids: set[str] = set()
    for index, entry in enumerate(entries):
        path = f"entries[{index}]"
        if not isinstance(entry, dict):
            errors.append(f"{path} must be an object")
            continue
        for field in ("id", "artifact_glob", "rationale", "owner"):
            if not isinstance(entry.get(field), str) or not entry[field]:
                errors.append(f"{path}.{field} must be a non-empty string")
        if entry.get("id") in ids:
            errors.append(f"{path}.id must be unique")
        ids.add(entry.get("id"))
        byte_range = entry.get("byte_range")
        replacement = entry.get("replacement_utf8")
        if not isinstance(byte_range, dict) or not isinstance(byte_range.get("start"), int) or not isinstance(byte_range.get("end"), int):
            errors.append(f"{path}.byte_range must contain exact integer start/end offsets")
        elif byte_range["start"] < 0 or byte_range["end"] <= byte_range["start"]:
            errors.append(f"{path}.byte_range is invalid")
        if not isinstance(replacement, str):
            errors.append(f"{path}.replacement_utf8 must be a string")
        elif isinstance(byte_range, dict) and isinstance(byte_range.get("start"), int) and isinstance(byte_range.get("end"), int):
            if len(replacement.encode("utf-8")) != byte_range["end"] - byte_range["start"]:
                errors.append(f"{path}.replacement_utf8 must preserve byte length")
    return entries, errors


def normalize(data: bytes, entry: dict[str, Any]) -> bytes:
    start, end = entry["byte_range"]["start"], entry["byte_range"]["end"]
    if end > len(data):
        raise ValueError("byte range exceeds artifact length")
    return data[:start] + entry["replacement_utf8"].encode("utf-8") + data[end:]


def compare(left: Path, right: Path, entries: list[dict[str, Any]]) -> tuple[dict[str, Any], list[str]]:
    errors: list[str] = []
    left_files, right_files = files(left), files(right)
    left_names, right_names = set(left_files), set(right_files)
    for name in sorted(left_names - right_names):
        errors.append(f"artifact exists only in left build: {name}")
    for name in sorted(right_names - left_names):
        errors.append(f"artifact exists only in right build: {name}")
    artifacts: list[dict[str, Any]] = []
    for name in sorted(left_names & right_names):
        left_path, right_path = left_files[name], right_files[name]
        left_mode = stat.S_IMODE(left_path.lstat().st_mode)
        right_mode = stat.S_IMODE(right_path.lstat().st_mode)
        left_raw, right_raw = raw_bytes(left_path), raw_bytes(right_path)
        item: dict[str, Any] = {
            "path": name,
            "left_raw_sha256": digest(left_raw),
            "right_raw_sha256": digest(right_raw),
            "left_normalized_sha256": digest(left_raw),
            "right_normalized_sha256": digest(right_raw),
            "mode": {"left": f"{left_mode:04o}", "right": f"{right_mode:04o}"},
        }
        if left_mode != right_mode:
            errors.append(f"artifact mode differs: {name}")
        if left_raw != right_raw:
            if core(name):
                errors.append(f"core artifact differs in raw bytes: {name}")
            else:
                matches = [entry for entry in entries if fnmatch.fnmatchcase(name, entry["artifact_glob"])]
                if len(matches) != 1:
                    errors.append(f"unlisted or ambiguous artifact difference: {name}")
                else:
                    try:
                        left_normalized = normalize(left_raw, matches[0])
                        right_normalized = normalize(right_raw, matches[0])
                    except ValueError as error:
                        errors.append(f"cannot normalize {name}: {error}")
                    else:
                        item["left_normalized_sha256"] = digest(left_normalized)
                        item["right_normalized_sha256"] = digest(right_normalized)
                        item["normalization_id"] = matches[0]["id"]
                        if left_normalized != right_normalized:
                            errors.append(f"normalized artifact still differs: {name}")
        artifacts.append(item)
    return {
        "schema_version": 1,
        "allowlist_version": 1,
        "left_root": str(left.resolve()),
        "right_root": str(right.resolve()),
        "artifacts": artifacts,
        "outcome": "PASS" if not errors else "FAIL",
    }, errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare complete package trees from two builds.")
    parser.add_argument("left", type=Path)
    parser.add_argument("right", type=Path)
    parser.add_argument("--allowlist", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.left.is_dir() or not args.right.is_dir():
        print("error: left and right must be package directories", file=sys.stderr)
        return 1
    try:
        allowlist = json.loads(args.allowlist.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        print(f"error: cannot read normalization allowlist: {error}", file=sys.stderr)
        return 1
    entries, errors = validate_allowlist(allowlist)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    report, errors = compare(args.left, args.right, entries)
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(encoded, encoding="utf-8")
    else:
        print(encoded, end="")
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
