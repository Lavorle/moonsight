from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any


_SHA256_PATTERN = re.compile(r"[0-9a-f]{64}")


REQUIRED_EVIDENCE_IDS: tuple[str, ...] = (
    "W1-ubuntu-chromium",
    "W1-ubuntu-firefox",
    "W1-fedora-chromium",
    "W1-fedora-firefox",
    "W1-arch-chromium",
    "W1-arch-firefox",
    "D1-ubuntu-appimage",
    "D1-ubuntu-deb",
    "D1-fedora-appimage",
    "D1-fedora-rpm",
    "D1-arch-appimage",
    "C1-web",
    "C1-desktop",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_object(path: Path, label: str) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read {label}: {error}") from error
    if not isinstance(data, dict):
        raise ValueError(f"{label} must be an object")
    return data


def validate_sha256(value: Any, path: str, errors: list[str]) -> str:
    if not isinstance(value, str) or _SHA256_PATTERN.fullmatch(value) is None:
        errors.append(
            f"{path} must be a 64-character lowercase hexadecimal SHA-256 digest"
        )
        return ""
    return value
