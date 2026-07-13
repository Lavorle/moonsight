#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import configparser
import hashlib
import io
import json
import os
import shlex
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any


WEB_NAME = "moonsight-web-x86_64-v1.0.0.zip"
APPIMAGE_NAME = "moonsight-linux-x86_64-v1.0.0.AppImage"
DEB_NAME = "moonsight-linux-x86_64-v1.0.0.deb"
RPM_NAME = "moonsight-linux-x86_64-v1.0.0.rpm"
EXPECTED_RELEASE_ARTIFACTS = {WEB_NAME, APPIMAGE_NAME, DEB_NAME, RPM_NAME}
IGNORED_BUILD_FILES = {"SHA256SUMS", "build-metadata.json"}
SAFE_NORMALIZABLE_METADATA_FIELDS = {
    "appimage": {"build_id"},
    "deb": set(),
    "rpm": {"build_host", "build_time"},
}
PayloadEntry = tuple[str, int, bytes]
PackageSnapshot = tuple[dict[str, str], dict[str, PayloadEntry]]


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def raw_bytes(path: Path) -> bytes:
    if path.is_symlink():
        return ("symlink:" + os.readlink(path)).encode("utf-8")
    return path.read_bytes()


def files(root: Path) -> dict[str, Path]:
    return {
        path.relative_to(root).as_posix(): path
        for path in root.rglob("*")
        if path.is_file() or path.is_symlink()
    }


def validate_policy(
    data: Any,
) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]], list[str]]:
    errors: list[str] = []
    if not isinstance(data, dict) or data.get("schema_version") != 1:
        return [], {}, ["normalization policy schema_version must be 1"]

    raw_packages = data.get("desktop_packages", [])
    if not isinstance(raw_packages, list):
        errors.append("normalization policy desktop_packages must be an array")
        raw_packages = []
    packages: dict[str, dict[str, Any]] = {}
    package_ids: set[str] = set()
    for index, package in enumerate(raw_packages):
        path = f"desktop_packages[{index}]"
        if not isinstance(package, dict):
            errors.append(f"{path} must be an object")
            continue
        for field in ("id", "artifact_name", "format", "rationale", "owner"):
            if not isinstance(package.get(field), str) or not package[field]:
                errors.append(f"{path}.{field} must be a non-empty string")
        if package.get("id") in package_ids:
            errors.append(f"{path}.id must be unique")
        package_ids.add(package.get("id"))
        artifact_name = package.get("artifact_name")
        if isinstance(artifact_name, str) and any(char in artifact_name for char in "*?["):
            errors.append(f"{path}.artifact_name must be an exact filename without globs")
        package_format = package.get("format")
        if package_format not in SAFE_NORMALIZABLE_METADATA_FIELDS:
            errors.append(f"{path}.format must be appimage, deb, or rpm")
        required_identity = package.get("required_identity")
        if not isinstance(required_identity, dict) or not required_identity:
            errors.append(f"{path}.required_identity must be a non-empty object")
        else:
            for field, value in required_identity.items():
                if not isinstance(field, str) or not field or not isinstance(value, str) or not value:
                    errors.append(
                        f"{path}.required_identity must map non-empty fields to non-empty strings"
                    )
                    break
        normalizable = package.get("normalizable_metadata_fields", [])
        if not isinstance(normalizable, list) or any(
            not isinstance(field, str) or not field for field in normalizable
        ):
            errors.append(f"{path}.normalizable_metadata_fields must be an array of strings")
            normalizable = []
        if package_format in SAFE_NORMALIZABLE_METADATA_FIELDS:
            unsupported = set(normalizable) - SAFE_NORMALIZABLE_METADATA_FIELDS[package_format]
            for field in sorted(unsupported):
                errors.append(f"{path} cannot normalize stable or product field: {field}")
        if isinstance(required_identity, dict):
            for field in sorted(set(normalizable) & set(required_identity)):
                errors.append(f"{path} cannot normalize required identity field: {field}")
        if isinstance(artifact_name, str) and artifact_name:
            if artifact_name in packages:
                errors.append(f"{path}.artifact_name must be unique")
            packages[artifact_name] = package

    entries = data.get("entries")
    if not isinstance(entries, list):
        errors.append("normalization policy entries must be an array")
        entries = []
    entry_ids: set[str] = set()
    entry_fields: set[tuple[Any, Any]] = set()
    packages_by_format = {
        package.get("format"): package
        for package in packages.values()
        if package.get("format") in SAFE_NORMALIZABLE_METADATA_FIELDS
    }
    for index, entry in enumerate(entries):
        path = f"entries[{index}]"
        if not isinstance(entry, dict):
            errors.append(f"{path} must be an object")
            continue
        if entry.get("namespace") != "package_metadata":
            errors.append(f"{path}.namespace must equal package_metadata")
        for forbidden in ("artifact_glob", "byte_range", "replacement_utf8"):
            if forbidden in entry:
                errors.append(f"{path}.{forbidden} is forbidden for metadata normalization")
        for field in ("id", "package_format", "field", "replacement", "rationale", "owner"):
            if not isinstance(entry.get(field), str) or not entry[field]:
                errors.append(f"{path}.{field} must be a non-empty string")
        if entry.get("id") in entry_ids:
            errors.append(f"{path}.id must be unique")
        entry_ids.add(entry.get("id"))
        pair = (entry.get("package_format"), entry.get("field"))
        if pair in entry_fields:
            errors.append(f"{path} duplicates metadata normalization for {pair[0]}.{pair[1]}")
        entry_fields.add(pair)
        package = packages_by_format.get(entry.get("package_format"))
        if package is None:
            errors.append(f"{path}.package_format must reference a configured desktop package")
        elif entry.get("field") not in package.get("normalizable_metadata_fields", []):
            errors.append(f"{path}.field is not an explicitly documented volatile field")
    return entries, packages, errors


def compare_trees(left: Path, right: Path) -> tuple[list[dict[str, Any]], list[str]]:
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
        if left_mode != right_mode:
            errors.append(f"artifact mode differs: {name}")
        if left_raw != right_raw:
            errors.append(f"artifact differs in raw bytes: {name}")
        artifacts.append(
            {
                "path": name,
                "left_size_bytes": len(left_raw),
                "right_size_bytes": len(right_raw),
                "left_raw_sha256": digest(left_raw),
                "right_raw_sha256": digest(right_raw),
                "left_normalized_sha256": digest(left_raw),
                "right_normalized_sha256": digest(right_raw),
                "mode": {"left": f"{left_mode:04o}", "right": f"{right_mode:04o}"},
                "comparison": "raw-complete-tree-entry",
            }
        )
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


def tar_member_inventory(name: str, data: bytes) -> dict[str, PayloadEntry]:
    if name.endswith(".zst"):
        result = subprocess.run(["zstd", "-dc"], input=data, capture_output=True, check=False)
        if result.returncode != 0:
            raise ValueError(
                f"cannot decompress {name}: {result.stderr.decode(errors='replace')}"
            )
        data = result.stdout
    return tar_inventory(data)


def parse_deb_control(data: bytes) -> dict[str, str]:
    fields: dict[str, str] = {}
    current = ""
    for line in data.decode("utf-8").splitlines():
        if line.startswith((" ", "\t")) and current:
            fields[current] += "\n" + line[1:]
            continue
        if ":" not in line:
            raise ValueError(f"invalid deb control line: {line}")
        key, value = line.split(":", 1)
        current = key.strip().lower().replace("-", "_")
        fields[current] = value.strip()
    for field in ("package", "version", "architecture"):
        if not fields.get(field):
            raise ValueError(f"deb identity missing {field}")
    fields["package_name"] = fields.pop("package")
    return fields


def deb_snapshot(path: Path) -> PackageSnapshot:
    members = ar_members(path.read_bytes())
    data_names = [name for name in members if name.startswith("data.tar")]
    control_names = [name for name in members if name.startswith("control.tar")]
    if len(data_names) != 1 or len(control_names) != 1:
        raise ValueError("deb archive must contain exactly one control.tar and data.tar")
    payload = tar_member_inventory(data_names[0], members[data_names[0]])
    control_inventory = tar_member_inventory(control_names[0], members[control_names[0]])
    control_entry = control_inventory.pop("control", None)
    if control_entry is None or control_entry[0] != "file":
        raise ValueError("deb identity missing control file")
    identity = parse_deb_control(control_entry[2])
    for name, entry in control_inventory.items():
        payload[f"@package-control/{name}"] = entry
    return identity, payload


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


def rpm_identity(path: Path) -> dict[str, str]:
    query = "%{NAME}\n%{VERSION}\n%{RELEASE}\n%{ARCH}\n%{BUILDTIME}\n%{BUILDHOST}\n"
    result = subprocess.run(
        ["rpm", "-qp", "--qf", query, str(path)],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise ValueError(f"rpm identity query failed: {result.stderr.strip()}")
    values = result.stdout.splitlines()
    if len(values) != 6:
        raise ValueError("rpm identity query returned an unexpected field count")
    fields = dict(
        zip(
            ("package_name", "version", "release", "architecture", "build_time", "build_host"),
            values,
            strict=True,
        )
    )
    for field in ("package_name", "version", "architecture"):
        if not fields[field] or fields[field] == "(none)":
            raise ValueError(f"rpm identity missing {field}")
    return fields


def rpm_snapshot(path: Path) -> PackageSnapshot:
    identity = rpm_identity(path)
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
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
        return identity, filesystem_inventory(root)


def parse_desktop_entry(path: Path) -> dict[str, str]:
    parser = configparser.ConfigParser(interpolation=None, strict=True)
    parser.optionxform = str
    try:
        parser.read_string(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, configparser.Error) as error:
        raise ValueError(f"cannot parse AppImage desktop entry: {error}") from error
    if "Desktop Entry" not in parser:
        raise ValueError("AppImage desktop entry is missing [Desktop Entry]")
    return dict(parser["Desktop Entry"])


def elf_architecture(path: Path) -> str:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"\x7fELF":
        raise ValueError("AppImage executable is not an ELF binary")
    byte_order = "<" if data[5] == 1 else ">" if data[5] == 2 else ""
    if not byte_order:
        raise ValueError("AppImage ELF has invalid byte order")
    machine = struct.unpack_from(byte_order + "H", data, 18)[0]
    if machine != 62:
        raise ValueError(f"AppImage executable architecture is not x86_64: ELF machine {machine}")
    return "x86_64"


def appimage_snapshot(path: Path) -> PackageSnapshot:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
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
        desktop_files = sorted(extracted.glob("*.desktop"))
        if len(desktop_files) != 1:
            raise ValueError("AppImage identity requires exactly one top-level desktop entry")
        desktop = parse_desktop_entry(desktop_files[0])
        app_name = desktop.get("Name", "").strip()
        exec_value = desktop.get("Exec", "").strip()
        # Prefer X-AppImage-Version; Tauri's default desktop omits it, so fall back to
        # Version= or the Formal 1.0 release artifact filename (...-v1.0.0.AppImage).
        version = desktop.get("X-AppImage-Version", "").strip()
        if not version:
            version = desktop.get("Version", "").strip()
        if not version:
            match = re.search(r"-v(\d+\.\d+\.\d+)\.AppImage$", path.name)
            if match is not None:
                version = match.group(1)
        if not app_name:
            raise ValueError("AppImage identity missing app_name")
        if not exec_value:
            raise ValueError("AppImage identity missing app_exec")
        if not version:
            raise ValueError("AppImage identity missing version")
        try:
            app_exec = Path(shlex.split(exec_value)[0]).name
        except (ValueError, IndexError) as error:
            raise ValueError("AppImage identity has invalid Exec field") from error
        candidates = [extracted / app_exec, extracted / "usr" / "bin" / app_exec]
        executables = [candidate for candidate in candidates if candidate.is_file()]
        if len(executables) != 1:
            raise ValueError("AppImage identity executable cannot be located uniquely")
        identity = {
            "app_name": app_name,
            "app_exec": app_exec,
            "version": version,
            "architecture": elf_architecture(executables[0]),
            "desktop_file": desktop_files[0].relative_to(extracted).as_posix(),
            "desktop_mode": f"{stat.S_IMODE(desktop_files[0].stat().st_mode):04o}",
        }
        if desktop.get("X-AppImage-BuildId", "").strip():
            identity["build_id"] = desktop["X-AppImage-BuildId"].strip()
        for key, value in sorted(desktop.items()):
            if key == "X-AppImage-BuildId":
                continue
            identity[f"desktop.{key}"] = value
        payload = filesystem_inventory(extracted)
        payload.pop(identity["desktop_file"])
        return identity, payload


def extracted_snapshot(path: Path, package_format: str) -> PackageSnapshot:
    if package_format == "appimage":
        return appimage_snapshot(path)
    if package_format == "deb":
        return deb_snapshot(path)
    if package_format == "rpm":
        return rpm_snapshot(path)
    raise ValueError(f"unsupported desktop package format: {package_format}")


def normalized_identity(
    identity: dict[str, str],
    package_format: str,
    entries: list[dict[str, Any]],
) -> tuple[dict[str, str], list[str]]:
    normalized = dict(identity)
    ids: list[str] = []
    for entry in entries:
        if entry["package_format"] == package_format and entry["field"] in normalized:
            normalized[entry["field"]] = entry["replacement"]
            ids.append(entry["id"])
    return normalized, ids


def payload_tree_digest(inventory: dict[str, PayloadEntry]) -> str:
    hasher = hashlib.sha256()
    for name, (kind, mode, data) in sorted(inventory.items()):
        for value in (
            name.encode("utf-8"),
            kind.encode("ascii"),
            f"{mode:04o}".encode("ascii"),
            data,
        ):
            hasher.update(len(value).to_bytes(8, "big"))
            hasher.update(value)
    return hasher.hexdigest()


def package_snapshot_digest(
    identity: dict[str, str], payload: dict[str, PayloadEntry]
) -> str:
    encoded_identity = json.dumps(
        identity, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return digest(encoded_identity + bytes.fromhex(payload_tree_digest(payload)))


def compare_snapshots(
    left: PackageSnapshot,
    right: PackageSnapshot,
    package: dict[str, Any],
    entries: list[dict[str, Any]],
) -> tuple[str, str, list[str], list[str]]:
    errors: list[str] = []
    package_format = package["format"]
    left_identity, left_payload = left
    right_identity, right_payload = right
    for side, identity in (("left", left_identity), ("right", right_identity)):
        for field, expected in package["required_identity"].items():
            if identity.get(field) != expected:
                errors.append(
                    f"{side} {package_format} identity {field} must equal {expected}"
                )
    left_normalized, left_ids = normalized_identity(left_identity, package_format, entries)
    right_normalized, right_ids = normalized_identity(right_identity, package_format, entries)
    for field in sorted(set(left_normalized) | set(right_normalized)):
        if left_normalized.get(field) != right_normalized.get(field):
            errors.append(f"desktop package identity differs: {field}")

    left_names, right_names = set(left_payload), set(right_payload)
    for name in sorted(left_names - right_names):
        errors.append(f"desktop payload exists only in left build: {name}")
    for name in sorted(right_names - left_names):
        errors.append(f"desktop payload exists only in right build: {name}")
    for name in sorted(left_names & right_names):
        left_kind, left_mode, left_data = left_payload[name]
        right_kind, right_mode, right_data = right_payload[name]
        if left_kind != right_kind:
            errors.append(f"desktop payload type differs: {name}")
        if left_mode != right_mode:
            errors.append(f"desktop payload mode differs: {name}")
        if left_data != right_data:
            errors.append(f"desktop payload differs in raw bytes: {name}")
    return (
        package_snapshot_digest(left_normalized, left_payload),
        package_snapshot_digest(right_normalized, right_payload),
        errors,
        sorted(set(left_ids) | set(right_ids)),
    )


def release_artifacts(root: Path) -> dict[str, Path]:
    return {
        path.name: path
        for path in root.iterdir()
        if path.is_file() and path.name not in IGNORED_BUILD_FILES
    }


def is_release_set(left: Path, right: Path) -> bool:
    return any(
        path.name in EXPECTED_RELEASE_ARTIFACTS
        or path.name in IGNORED_BUILD_FILES
        or path.suffix in {".zip", ".AppImage", ".deb", ".rpm"}
        for root in (left, right)
        for path in root.iterdir()
        if path.is_file()
    )


def validate_release_names(side: str, names: set[str], errors: list[str]) -> None:
    for name in sorted(EXPECTED_RELEASE_ARTIFACTS - names):
        errors.append(f"{side} release set missing required artifact: {name}")
    for name in sorted(names - EXPECTED_RELEASE_ARTIFACTS):
        errors.append(f"{side} release set has unexpected artifact: {name}")


def compare_release_sets(
    left: Path,
    right: Path,
    entries: list[dict[str, Any]],
    packages: dict[str, dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[str]]:
    errors: list[str] = []
    left_files, right_files = release_artifacts(left), release_artifacts(right)
    left_names, right_names = set(left_files), set(right_files)
    validate_release_names("left", left_names, errors)
    validate_release_names("right", right_names, errors)
    artifacts: list[dict[str, Any]] = []
    for name in sorted(EXPECTED_RELEASE_ARTIFACTS & left_names & right_names):
        left_path, right_path = left_files[name], right_files[name]
        left_raw, right_raw = left_path.read_bytes(), right_path.read_bytes()
        item: dict[str, Any] = {
            "path": name,
            "left_size_bytes": len(left_raw),
            "right_size_bytes": len(right_raw),
            "left_raw_sha256": digest(left_raw),
            "right_raw_sha256": digest(right_raw),
        }
        if name == WEB_NAME:
            item["comparison"] = "raw-web-zip"
            item["left_normalized_sha256"] = item["left_raw_sha256"]
            item["right_normalized_sha256"] = item["right_raw_sha256"]
            if left_raw != right_raw:
                errors.append(f"web ZIP differs in raw bytes: {name}")
        else:
            package = packages.get(name)
            if package is None:
                errors.append(f"normalization policy does not configure desktop artifact: {name}")
                item["left_normalized_sha256"] = item["left_raw_sha256"]
                item["right_normalized_sha256"] = item["right_raw_sha256"]
            else:
                item["comparison"] = "normalized-desktop-payload-and-identity"
                try:
                    left_snapshot = extracted_snapshot(left_path, package["format"])
                    right_snapshot = extracted_snapshot(right_path, package["format"])
                except (OSError, ValueError) as error:
                    errors.append(f"cannot extract desktop package {name}: {error}")
                    item["left_normalized_sha256"] = item["left_raw_sha256"]
                    item["right_normalized_sha256"] = item["right_raw_sha256"]
                else:
                    left_digest, right_digest, snapshot_errors, normalization_ids = (
                        compare_snapshots(left_snapshot, right_snapshot, package, entries)
                    )
                    item["left_normalized_sha256"] = left_digest
                    item["right_normalized_sha256"] = right_digest
                    item["identity"] = {
                        "left": left_snapshot[0],
                        "right": right_snapshot[0],
                    }
                    if normalization_ids:
                        item["normalization_ids"] = normalization_ids
                    errors.extend(snapshot_errors)
        artifacts.append(item)
    return artifacts, errors


def reproducibility_input_digest(
    policy_sha256: str, artifacts: list[dict[str, Any]]
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
        description="Compare complete trees or exact Formal 1.0 release artifact sets."
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
        policy = json.loads(policy_bytes.decode("utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        print(f"error: cannot read normalization policy: {error}", file=sys.stderr)
        return 1
    entries, packages, errors = validate_policy(policy)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    if is_release_set(args.left, args.right):
        artifacts, errors = compare_release_sets(args.left, args.right, entries, packages)
    else:
        artifacts, errors = compare_trees(args.left, args.right)
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
