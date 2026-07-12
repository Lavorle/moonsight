#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")
DIGEST_PATTERN = re.compile(r"^[0-9a-f]{64}$")
STATUSES = {"PASS", "FAIL", "BLOCKED", "NOT_RUN"}
EXTERNAL_CHECKS = ("W1", "D1", "C1")


def require_object(value: Any, path: str, errors: list[str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        errors.append(f"{path} must be an object")
        return {}
    return value


def require_list(value: Any, path: str, errors: list[str]) -> list[Any]:
    if not isinstance(value, list):
        errors.append(f"{path} must be an array")
        return []
    return value


def require_text(value: Any, path: str, errors: list[str]) -> str:
    if not isinstance(value, str) or not value:
        errors.append(f"{path} must be a non-empty string")
        return ""
    return value


def require_pattern(
    value: Any, path: str, pattern: re.Pattern[str], errors: list[str]
) -> str:
    text = require_text(value, path, errors)
    if text and pattern.fullmatch(text) is None:
        errors.append(f"{path} has an invalid format")
    return text


def validate_manifest(data: Any, require_release_ready: bool) -> list[str]:
    errors: list[str] = []
    root = require_object(data, "manifest", errors)

    if root.get("schema_version") != 1:
        errors.append("schema_version must be 1")

    candidate = require_object(root.get("candidate"), "candidate", errors)
    candidate_commit = require_pattern(
        candidate.get("commit"), "candidate.commit", SHA_PATTERN, errors
    )

    toolchains = require_object(candidate.get("toolchains"), "candidate.toolchains", errors)
    if not toolchains:
        errors.append("candidate.toolchains must not be empty")
    for name, version in toolchains.items():
        require_text(name, "candidate.toolchains key", errors)
        require_text(version, f"candidate.toolchains.{name}", errors)

    artifact_paths: set[str] = set()
    artifacts = require_list(candidate.get("artifacts"), "candidate.artifacts", errors)
    if not artifacts:
        errors.append("candidate.artifacts must not be empty")
    for index, raw_artifact in enumerate(artifacts):
        path = f"candidate.artifacts[{index}]"
        artifact = require_object(raw_artifact, path, errors)
        artifact_path = require_text(artifact.get("path"), f"{path}.path", errors)
        if artifact_path:
            if artifact_path in artifact_paths:
                errors.append(f"{path}.path duplicates {artifact_path}")
            artifact_paths.add(artifact_path)
        require_pattern(artifact.get("sha256"), f"{path}.sha256", DIGEST_PATTERN, errors)
        if "normalized_sha256" in artifact:
            require_pattern(
                artifact.get("normalized_sha256"),
                f"{path}.normalized_sha256",
                DIGEST_PATTERN,
                errors,
            )

    generated_files = require_list(
        root.get("generated_files"), "generated_files", errors
    )
    for index, raw_generated in enumerate(generated_files):
        path = f"generated_files[{index}]"
        generated = require_object(raw_generated, path, errors)
        require_text(generated.get("path"), f"{path}.path", errors)
        require_text(generated.get("generator"), f"{path}.generator", errors)
        require_text(generated.get("owner"), f"{path}.owner", errors)
        if generated.get("clean") is not True:
            errors.append(f"{path}.clean must be true")

    automated_checks = require_list(
        root.get("automated_checks"), "automated_checks", errors
    )
    if not automated_checks:
        errors.append("automated_checks must not be empty")
    for index, raw_check in enumerate(automated_checks):
        path = f"automated_checks[{index}]"
        check = require_object(raw_check, path, errors)
        require_text(check.get("name"), f"{path}.name", errors)
        status = require_text(check.get("status"), f"{path}.status", errors)
        if status and status not in STATUSES:
            errors.append(f"{path}.status must be one of {sorted(STATUSES)}")
        commit = require_pattern(check.get("commit"), f"{path}.commit", SHA_PATTERN, errors)
        if candidate_commit and commit and commit != candidate_commit:
            errors.append(f"{path}.commit must equal candidate.commit")
        require_text(check.get("output"), f"{path}.output", errors)
        if require_release_ready and status != "PASS":
            errors.append(f"{path}.status must be PASS")

    external = require_object(root.get("external_checks"), "external_checks", errors)
    for name in EXTERNAL_CHECKS:
        path = f"external_checks.{name}"
        check = require_object(external.get(name), path, errors)
        status = require_text(check.get("status"), f"{path}.status", errors)
        if status and status not in STATUSES:
            errors.append(f"{path}.status must be one of {sorted(STATUSES)}")
        commit = require_pattern(check.get("commit"), f"{path}.commit", SHA_PATTERN, errors)
        if candidate_commit and commit and commit != candidate_commit:
            errors.append(f"{path}.commit must equal candidate.commit")
        references = require_list(check.get("artifacts"), f"{path}.artifacts", errors)
        for index, reference in enumerate(references):
            artifact = require_text(reference, f"{path}.artifacts[{index}]", errors)
            if artifact and artifact not in artifact_paths:
                errors.append(
                    f"{path}.artifacts[{index}] does not reference candidate.artifacts"
                )
        if require_release_ready and status != "PASS":
            errors.append(f"{path}.status must be PASS")

    authorization = root.get("release_authorized")
    if not isinstance(authorization, bool):
        errors.append("release_authorized must be a boolean")
    elif require_release_ready and authorization is not True:
        errors.append("release_authorized must be true")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate Formal 1.0 exact-SHA release evidence."
    )
    parser.add_argument(
        "--require-release-ready",
        action="store_true",
        help="also require automated, W1, D1, C1, and authorization gates to pass",
    )
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()

    try:
        data = json.loads(args.manifest.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        print(f"error: cannot read evidence manifest: {error}", file=sys.stderr)
        return 1

    errors = validate_manifest(data, args.require_release_ready)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    if args.require_release_ready:
        print("OK: release-ready evidence is consistent")
    else:
        print("OK: schema and exact-SHA evidence are consistent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
