#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import io
import json
import os
import stat
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any


CORE_GLOBS = (
    "*.msb", "**/*.msb", "*.msb2", "**/*.msb2",
    "*.catalog", "**/*.catalog", "*.catalog.json", "**/*.catalog.json",
    "manifest.json", "**/manifest.json", "*.wasm", "**/*.wasm",
    "*.js", "**/*.js", "*.mjs", "**/*.mjs", "*.cjs", "**/*.cjs",
    "*.css", "**/*.css", "*.html", "**/*.html", "*.json", "**/*.json",
    "*.map", "**/*.map",
    "*.exe", "**/*.exe", "*.dll", "**/*.dll", "*.so", "**/*.so",
    "*.dylib", "**/*.dylib",
    "*.png", "**/*.png", "*.jpg", "**/*.jpg", "*.jpeg", "**/*.jpeg",
    "*.webp", "**/*.webp", "*.svg", "**/*.svg", "*.ogg", "**/*.ogg",
    "*.mp3", "**/*.mp3", "*.wav", "**/*.wav", "*.flac", "**/*.flac",
    "*.ttf", "**/*.ttf", "*.otf", "**/*.otf", "*.woff", "**/*.woff",
    "*.woff2", "**/*.woff2",
)
RELEASE_SUFFIXES = (".zip", ".AppImage", ".deb", ".rpm")
IGNORED_BUILD_FILES = {"SHA256SUMS", "build-metadata.json"}
PayloadEntry = tuple[str, int, bytes]


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


def validate_allowlist(
    data: Any,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[str]]:
    errors: list[str] = []
    if not isinstance(data, dict) or data.get("schema_version") != 1:
        return [], [], ["normalization allowlist schema_version must be 1"]
    entries = data.get("entries")
    if not isinstance(entries, list):
        return [], [], ["normalization allowlist entries must be an array"]
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
        if (
            not isinstance(byte_range, dict)
            or not isinstance(byte_range.get("start"), int)
            or not isinstance(byte_range.get("end"), int)
        ):
            errors.append(f"{path}.byte_range must contain exact integer start/end offsets")
        elif byte_range["start"] < 0 or byte_range["end"] <= byte_range["start"]:
            errors.append(f"{path}.byte_range is invalid")
        if not isinstance(replacement, str):
            errors.append(f"{path}.replacement_utf8 must be a string")
        elif (
            isinstance(byte_range, dict)
            and isinstance(byte_range.get("start"), int)
            and isinstance(byte_range.get("end"), int)
            and len(replacement.encode("utf-8"))
            != byte_range["end"] - byte_range["start"]
        ):
            errors.append(f"{path}.replacement_utf8 must preserve byte length")

    packages = data.get("desktop_packages", [])
    if not isinstance(packages, list):
        errors.append("normalization allowlist desktop_packages must be an array")
        packages = []
    package_ids: set[str] = set()
    for index, package in enumerate(packages):
        path = f"desktop_packages[{index}]"
        if not isinstance(package, dict):
            errors.append(f"{path} must be an object")
            continue
        for field in ("id", "artifact_glob", "format", "rationale", "owner"):
            if not isinstance(package.get(field), str) or not package[field]:
                errors.append(f"{path}.{field} must be a non-empty string")
        if package.get("id") in package_ids:
            errors.append(f"{path}.id must be unique")
        package_ids.add(package.get("id"))
        if package.get("format") not in {"appimage", "deb", "rpm"}:
            errors.append(f"{path}.format must be appimage, deb, or rpm")
    return entries, packages, errors


def normalize(data: bytes, entry: dict[str, Any]) -> bytes:
    start, end = entry["byte_range"]["start"], entry["byte_range"]["end"]
    if end > len(data):
        raise ValueError("byte range exceeds artifact length")
    return data[:start] + entry["replacement_utf8"].encode("utf-8") + data[end:]


def normalized_bytes(
    name: str,
    data: bytes,
    entries: list[dict[str, Any]],
    errors: list[str],
    *,
    error_prefix: str,
) -> tuple[bytes, str | None]:
    if core(name):
        errors.append(f"{error_prefix}: {name}")
        return data, None
    matches = [entry for entry in entries if fnmatch.fnmatchcase(name, entry["artifact_glob"])]
    if len(matches) != 1:
        errors.append(f"unlisted or ambiguous artifact difference: {name}")
        return data, None
    try:
        return normalize(data, matches[0]), matches[0]["id"]
    except ValueError as error:
        errors.append(f"cannot normalize {name}: {error}")
        return data, matches[0]["id"]


def compare_trees(
    left: Path,
    right: Path,
    entries: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[str]]:
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
        left_normalized, right_normalized = left_raw, right_raw
        normalization_id: str | None = None
        if left_mode != right_mode:
            errors.append(f"artifact mode differs: {name}")
        if left_raw != right_raw:
            if core(name):
                errors.append(f"core artifact differs in raw bytes: {name}")
            else:
                left_normalized, normalization_id = normalized_bytes(
                    name,
                    left_raw,
                    entries,
                    errors,
                    error_prefix="core artifact differs in raw bytes",
                )
                if normalization_id is not None:
                    right_errors: list[str] = []
                    right_normalized, _ = normalized_bytes(
                        name,
                        right_raw,
                        entries,
                        right_errors,
                        error_prefix="core artifact differs in raw bytes",
                    )
                    errors.extend(right_errors)
                    if left_normalized != right_normalized:
                        errors.append(f"normalized artifact still differs: {name}")
        item: dict[str, Any] = {
            "path": name,
            "left_size_bytes": len(left_raw),
            "right_size_bytes": len(right_raw),
            "left_raw_sha256": digest(left_raw),
            "right_raw_sha256": digest(right_raw),
            "left_normalized_sha256": digest(left_normalized),
            "right_normalized_sha256": digest(right_normalized),
            "mode": {"left": f"{left_mode:04o}", "right": f"{right_mode:04o}"},
            "comparison": "complete-tree-entry",
        }
        if normalization_id is not None:
            item["normalization_id"] = normalization_id
        artifacts.append(item)
    return artifacts, errors


def safe_tar_name(name: str) -> str:
    normalized = name.removeprefix("./")
    pure = PurePosixPath(normalized)
    if not normalized or pure.is_absolute() or ".." in pure.parts:
        raise ValueError(f"unsafe archive path: {name}")
    return pure.as_posix()


def tar_inventory(data: bytes) -> dict[str, PayloadEntry]:
    inventory: dict[str, PayloadEntry] = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as archive:
        for member in archive.getmembers():
            name = safe_tar_name(member.name)
            mode = stat.S_IMODE(member.mode)
            if member.isdir():
                inventory[name] = ("directory", mode, b"")
            elif member.issym():
                inventory[name] = ("symlink", mode, member.linkname.encode("utf-8"))
            elif member.islnk():
                inventory[name] = ("hardlink", mode, member.linkname.encode("utf-8"))
            elif member.isfile():
                extracted = archive.extractfile(member)
                if extracted is None:
                    raise ValueError(f"cannot read archive member: {name}")
                inventory[name] = ("file", mode, extracted.read())
            else:
                inventory[name] = ("special", mode, member.type)
    return inventory


def ar_members(data: bytes) -> dict[str, bytes]:
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("deb archive has invalid ar signature")
    members: dict[str, bytes] = {}
    offset = 8
    while offset < len(data):
        if offset + 60 > len(data):
            raise ValueError("deb archive has truncated ar header")
        header = data[offset : offset + 60]
        if header[58:60] != b"`\n":
            raise ValueError("deb archive has invalid ar member header")
        name = header[:16].decode("ascii").strip().removesuffix("/")
        try:
            size = int(header[48:58].decode("ascii").strip())
        except ValueError as error:
            raise ValueError("deb archive has invalid ar member size") from error
        start, end = offset + 60, offset + 60 + size
        if end > len(data):
            raise ValueError("deb archive has truncated ar member")
        members[name] = data[start:end]
        offset = end + (size % 2)
    return members


def deb_inventory(path: Path) -> dict[str, PayloadEntry]:
    members = ar_members(path.read_bytes())
    data_names = [name for name in members if name.startswith("data.tar")]
    if len(data_names) != 1:
        raise ValueError("deb archive must contain exactly one data.tar payload")
    name = data_names[0]
    payload = members[name]
    if name.endswith(".zst"):
        result = subprocess.run(
            ["zstd", "-dc"],
            input=payload,
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            raise ValueError(f"cannot decompress deb data.tar.zst: {result.stderr.decode(errors='replace')}")
        payload = result.stdout
    return tar_inventory(payload)


def filesystem_inventory(root: Path) -> dict[str, PayloadEntry]:
    inventory: dict[str, PayloadEntry] = {}
    for path in sorted(root.rglob("*")):
        name = path.relative_to(root).as_posix()
        mode = stat.S_IMODE(path.lstat().st_mode)
        if path.is_symlink():
            inventory[name] = ("symlink", mode, os.readlink(path).encode("utf-8"))
        elif path.is_dir():
            inventory[name] = ("directory", mode, b"")
        elif path.is_file():
            inventory[name] = ("file", mode, path.read_bytes())
        else:
            inventory[name] = ("special", mode, b"")
    return inventory


def extracted_inventory(path: Path, package_format: str) -> dict[str, PayloadEntry]:
    if package_format == "deb":
        return deb_inventory(path)
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        if package_format == "rpm":
            rpm = subprocess.run(["rpm2cpio", str(path)], capture_output=True, check=False)
            if rpm.returncode != 0:
                raise ValueError(f"rpm2cpio failed: {rpm.stderr.decode(errors='replace')}")
            cpio = subprocess.run(
                ["cpio", "-idm", "--quiet", "--no-absolute-filenames"],
                cwd=root,
                input=rpm.stdout,
                capture_output=True,
                check=False,
            )
            if cpio.returncode != 0:
                raise ValueError(f"cpio extraction failed: {cpio.stderr.decode(errors='replace')}")
            return filesystem_inventory(root)
        if package_format == "appimage":
            result = subprocess.run(
                [str(path.resolve()), "--appimage-extract"],
                cwd=root,
                capture_output=True,
                check=False,
            )
            extracted = root / "squashfs-root"
            if result.returncode != 0 or not extracted.is_dir():
                detail = result.stderr.decode(errors="replace").strip()
                raise ValueError(f"AppImage extraction failed: {detail or 'no squashfs-root'}")
            return filesystem_inventory(extracted)
    raise ValueError(f"unsupported desktop package format: {package_format}")


def payload_tree_digest(inventory: dict[str, PayloadEntry]) -> str:
    hasher = hashlib.sha256()
    for name, (kind, mode, data) in sorted(inventory.items()):
        encoded_name = name.encode("utf-8")
        encoded_kind = kind.encode("ascii")
        for value in (encoded_name, encoded_kind, f"{mode:04o}".encode("ascii"), data):
            hasher.update(len(value).to_bytes(8, "big"))
            hasher.update(value)
    return hasher.hexdigest()


def compare_payloads(
    left: dict[str, PayloadEntry],
    right: dict[str, PayloadEntry],
    entries: list[dict[str, Any]],
) -> tuple[str, str, list[str]]:
    errors: list[str] = []
    left_normalized = dict(left)
    right_normalized = dict(right)
    left_names, right_names = set(left), set(right)
    for name in sorted(left_names - right_names):
        errors.append(f"desktop payload exists only in left build: {name}")
    for name in sorted(right_names - left_names):
        errors.append(f"desktop payload exists only in right build: {name}")
    for name in sorted(left_names & right_names):
        left_kind, left_mode, left_data = left[name]
        right_kind, right_mode, right_data = right[name]
        if left_kind != right_kind:
            errors.append(f"desktop payload type differs: {name}")
        if left_mode != right_mode:
            errors.append(f"desktop payload mode differs: {name}")
        if left_data != right_data:
            if core(name) or left_mode & 0o111 or right_mode & 0o111:
                errors.append(f"desktop payload differs in raw bytes: {name}")
                continue
            normalization_errors: list[str] = []
            normalized_left, normalization_id = normalized_bytes(
                name,
                left_data,
                entries,
                normalization_errors,
                error_prefix="desktop payload differs in raw bytes",
            )
            errors.extend(normalization_errors)
            if normalization_id is not None:
                right_errors: list[str] = []
                normalized_right, _ = normalized_bytes(
                    name,
                    right_data,
                    entries,
                    right_errors,
                    error_prefix="desktop payload differs in raw bytes",
                )
                errors.extend(right_errors)
                left_normalized[name] = (left_kind, left_mode, normalized_left)
                right_normalized[name] = (right_kind, right_mode, normalized_right)
                if normalized_left != normalized_right:
                    errors.append(f"normalized desktop payload still differs: {name}")
    return (
        payload_tree_digest(left_normalized),
        payload_tree_digest(right_normalized),
        errors,
    )


def release_artifacts(root: Path) -> dict[str, Path]:
    return {
        path.name: path
        for path in root.iterdir()
        if path.is_file() and path.name not in IGNORED_BUILD_FILES
    }


def is_release_set(left: Path, right: Path) -> bool:
    return any(
        path.is_file() and path.name.endswith(RELEASE_SUFFIXES)
        for root in (left, right)
        for path in root.iterdir()
    )


def compare_release_sets(
    left: Path,
    right: Path,
    entries: list[dict[str, Any]],
    packages: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[str]]:
    errors: list[str] = []
    left_files, right_files = release_artifacts(left), release_artifacts(right)
    left_names, right_names = set(left_files), set(right_files)
    for name in sorted(left_names - right_names):
        errors.append(f"artifact exists only in left build: {name}")
    for name in sorted(right_names - left_names):
        errors.append(f"artifact exists only in right build: {name}")
    artifacts: list[dict[str, Any]] = []
    for name in sorted(left_names & right_names):
        left_path, right_path = left_files[name], right_files[name]
        left_raw, right_raw = left_path.read_bytes(), right_path.read_bytes()
        item: dict[str, Any] = {
            "path": name,
            "left_size_bytes": len(left_raw),
            "right_size_bytes": len(right_raw),
            "left_raw_sha256": digest(left_raw),
            "right_raw_sha256": digest(right_raw),
        }
        if name.endswith(".zip"):
            item["comparison"] = "raw-web-zip"
            item["left_normalized_sha256"] = item["left_raw_sha256"]
            item["right_normalized_sha256"] = item["right_raw_sha256"]
            if left_raw != right_raw:
                errors.append(f"web ZIP differs in raw bytes: {name}")
        else:
            matches = [
                package
                for package in packages
                if fnmatch.fnmatchcase(name, package["artifact_glob"])
            ]
            if len(matches) != 1:
                errors.append(f"unlisted or ambiguous desktop package: {name}")
                item["left_normalized_sha256"] = item["left_raw_sha256"]
                item["right_normalized_sha256"] = item["right_raw_sha256"]
            else:
                item["comparison"] = "normalized-desktop-payload"
                item["normalization_id"] = matches[0]["id"]
                try:
                    left_payload = extracted_inventory(left_path, matches[0]["format"])
                    right_payload = extracted_inventory(right_path, matches[0]["format"])
                except (OSError, ValueError) as error:
                    errors.append(f"cannot extract desktop package {name}: {error}")
                    item["left_normalized_sha256"] = item["left_raw_sha256"]
                    item["right_normalized_sha256"] = item["right_raw_sha256"]
                else:
                    left_digest, right_digest, payload_errors = compare_payloads(
                        left_payload, right_payload, entries
                    )
                    item["left_normalized_sha256"] = left_digest
                    item["right_normalized_sha256"] = right_digest
                    errors.extend(payload_errors)
        artifacts.append(item)
    return artifacts, errors


def reproducibility_input_digest(
    policy_sha256: str,
    artifacts: list[dict[str, Any]],
) -> str:
    inputs = {
        "policy_sha256": policy_sha256,
        "artifacts": [
            {
                "path": item["path"],
                "left_size_bytes": item["left_size_bytes"],
                "right_size_bytes": item["right_size_bytes"],
                "left_raw_sha256": item["left_raw_sha256"],
                "right_raw_sha256": item["right_raw_sha256"],
            }
            for item in artifacts
        ],
    }
    return digest(json.dumps(inputs, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare complete trees or versioned Formal 1.0 release artifact sets."
    )
    parser.add_argument("left", type=Path)
    parser.add_argument("right", type=Path)
    parser.add_argument("--allowlist", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.left.is_dir() or not args.right.is_dir():
        print("error: left and right must be package directories", file=sys.stderr)
        return 1
    try:
        policy_bytes = args.allowlist.read_bytes()
        allowlist = json.loads(policy_bytes.decode("utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        print(f"error: cannot read normalization allowlist: {error}", file=sys.stderr)
        return 1
    entries, packages, errors = validate_allowlist(allowlist)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    if is_release_set(args.left, args.right):
        artifacts, errors = compare_release_sets(
            args.left, args.right, entries, packages
        )
    else:
        artifacts, errors = compare_trees(args.left, args.right, entries)
    report = {
        "schema_version": 1,
        "allowlist_version": 1,
        "input_sha256": reproducibility_input_digest(digest(policy_bytes), artifacts),
        "left_root": str(args.left.resolve()),
        "right_root": str(args.right.resolve()),
        "artifacts": artifacts,
        "outcome": "PASS" if not errors else "FAIL",
    }
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
