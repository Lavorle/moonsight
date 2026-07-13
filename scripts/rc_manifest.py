#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from release_schema import (
    REQUIRED_EVIDENCE_IDS,
    read_object,
    sha256_file,
    validate_sha256,
)


SHA = re.compile(r"^[0-9a-f]{40}$")
CHECK_STATUSES = {"PASS", "FAIL", "BLOCKED", "NOT_RUN"}
AUTOMATED_CHECK_IDS = ("benchmark", "reproducibility")
PUBLICATION_NOTICE = "Candidate identity does not authorize publication."


def check_status(report: dict[str, Any]) -> str:
    outcome = report.get("outcome")
    return outcome if outcome in CHECK_STATUSES else "FAIL"


def combined_status(*statuses: str) -> str:
    if all(status == "PASS" for status in statuses):
        return "PASS"
    if "FAIL" in statuses:
        return "FAIL"
    if "BLOCKED" in statuses:
        return "BLOCKED"
    return "NOT_RUN"


def require_non_empty_string(
    value: Any,
    path: str,
    errors: list[str],
) -> str:
    if not isinstance(value, str) or not value:
        errors.append(f"{path} must be a non-empty string")
        return ""
    return value


def require_version_map(
    value: Any,
    path: str,
    required_keys: tuple[str, ...],
    errors: list[str],
) -> dict[str, Any]:
    if not isinstance(value, dict):
        errors.append(f"{path} must be an object")
        return {}
    for key in required_keys:
        require_non_empty_string(value.get(key), f"{path}.{key}", errors)
    return value


def require_object(value: Any, path: str, errors: list[str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        errors.append(f"{path} must be an object")
        return {}
    return value


def require_array(value: Any, path: str, errors: list[str]) -> list[Any]:
    if not isinstance(value, list):
        errors.append(f"{path} must be an array")
        return []
    return value


def validate_report_reference(
    value: Any, path: str, errors: list[str]
) -> dict[str, Any]:
    report = require_object(value, path, errors)
    require_non_empty_string(report.get("path"), f"{path}.path", errors)
    validate_sha256(report.get("sha256"), f"{path}.sha256", errors)
    return report


def validate_candidate_manifest(manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if manifest.get("schema_version") != 2:
        errors.append("candidate.schema_version must be 2")
    require_non_empty_string(
        manifest.get("attempt_id"), "candidate.attempt_id", errors
    )

    identity = require_object(manifest.get("candidate"), "candidate", errors)
    if identity.get("version") != "v1.0.0":
        errors.append("candidate.version must equal v1.0.0")
    commit = require_non_empty_string(
        identity.get("commit"), "candidate.commit", errors
    )
    if commit and SHA.fullmatch(commit) is None:
        errors.append("candidate.commit must be a full lowercase Git SHA")
    if identity.get("architecture") != "x86_64":
        errors.append("candidate.architecture must equal x86_64")
    if identity.get("clean_tree") is not True:
        errors.append("candidate.clean_tree must be true")
    require_non_empty_string(
        identity.get("built_at_utc"), "candidate.built_at_utc", errors
    )
    require_non_empty_string(
        identity.get("build_host"), "candidate.build_host", errors
    )

    artifacts = require_array(
        identity.get("artifacts"), "candidate.artifacts", errors
    )
    if not artifacts:
        errors.append("candidate.artifacts must be a non-empty array")
    artifact_paths: set[str] = set()
    for index, raw_artifact in enumerate(artifacts):
        path = f"candidate.artifacts[{index}]"
        artifact = require_object(raw_artifact, path, errors)
        artifact_path = require_non_empty_string(
            artifact.get("path"), f"{path}.path", errors
        )
        if artifact_path in artifact_paths:
            errors.append(f"{path}.path duplicates candidate artifact {artifact_path}")
        elif artifact_path:
            artifact_paths.add(artifact_path)
        size = artifact.get("size_bytes")
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            errors.append(f"{path}.size_bytes must be a non-negative integer")
        validate_sha256(artifact.get("sha256"), f"{path}.sha256", errors)

    require_version_map(
        manifest.get("toolchains"),
        "candidate.toolchains",
        ("moon", "node", "rustc", "tauri_cli"),
        errors,
    )
    require_version_map(
        manifest.get("system"),
        "candidate.system",
        ("build_os", "kernel", "fedora", "arch"),
        errors,
    )
    require_version_map(
        manifest.get("validation_targets"),
        "candidate.validation_targets",
        ("chromium", "firefox", "webkitgtk"),
        errors,
    )

    reproducibility = require_object(
        manifest.get("reproducibility"), "candidate.reproducibility", errors
    )
    reproducibility_input = validate_sha256(
        reproducibility.get("input_sha256"),
        "candidate.reproducibility.input_sha256",
        errors,
    )
    reproducibility_report = validate_report_reference(
        reproducibility.get("report"),
        "candidate.reproducibility.report",
        errors,
    )

    if manifest.get("required_evidence_ids") != list(REQUIRED_EVIDENCE_IDS):
        errors.append("candidate.required_evidence_ids must equal the Formal 1.0 matrix")

    checks = require_array(
        manifest.get("automated_checks"), "candidate.automated_checks", errors
    )
    seen: set[str] = set()
    duplicates: set[str] = set()
    by_id: dict[str, dict[str, Any]] = {}
    for index, raw_check in enumerate(checks):
        path = f"candidate.automated_checks[{index}]"
        check = require_object(raw_check, path, errors)
        check_id = check.get("id")
        if check_id not in AUTOMATED_CHECK_IDS:
            errors.append(f"{path}.id is not a required automated check")
        elif check_id in seen:
            duplicates.add(check_id)
        else:
            seen.add(check_id)
            by_id[check_id] = check
        if check.get("status") not in CHECK_STATUSES:
            errors.append(f"{path}.status is invalid")
        validate_sha256(check.get("input_sha256"), f"{path}.input_sha256", errors)
        validate_report_reference(check.get("report"), f"{path}.report", errors)
    for check_id in sorted(duplicates):
        errors.append(f"duplicate automated check ID: {check_id}")
    missing_checks = [check_id for check_id in AUTOMATED_CHECK_IDS if check_id not in seen]
    if missing_checks:
        errors.append(f"missing automated check IDs: {', '.join(missing_checks)}")
    reproducibility_check = by_id.get("reproducibility", {})
    if (
        reproducibility_input
        and reproducibility_check.get("input_sha256") != reproducibility_input
    ):
        errors.append(
            "candidate reproducibility automated check input must equal "
            "candidate.reproducibility.input_sha256"
        )
    if (
        reproducibility_report
        and reproducibility_check.get("report") != reproducibility_report
    ):
        errors.append(
            "candidate reproducibility automated check report must equal "
            "candidate.reproducibility.report"
        )

    if manifest.get("notice") != PUBLICATION_NOTICE:
        errors.append(f"candidate.notice must equal {PUBLICATION_NOTICE}")
    if "external_checks" in manifest:
        errors.append("candidate must not contain external_checks")
    if "release_authorized" in manifest:
        errors.append("candidate must not contain release_authorized")
    return errors


def generate(args: argparse.Namespace) -> int:
    if SHA.fullmatch(args.candidate) is None:
        print("error: candidate must be a full 40-character lowercase Git SHA", file=sys.stderr)
        return 1
    try:
        benchmark = read_object(args.benchmark, "benchmark report")
        repro = read_object(args.reproducibility, "reproducibility report")
        metadata = read_object(args.metadata, "RC metadata")
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    errors: list[str] = []
    require_non_empty_string(metadata.get("attempt_id"), "metadata.attempt_id", errors)
    if metadata.get("clean_tree") is not True:
        errors.append("metadata.clean_tree must be true")
    require_non_empty_string(metadata.get("built_at_utc"), "metadata.built_at_utc", errors)
    require_non_empty_string(metadata.get("build_host"), "metadata.build_host", errors)
    require_version_map(
        metadata.get("toolchains"),
        "metadata.toolchains",
        ("moon", "node", "rustc", "tauri_cli"),
        errors,
    )
    require_version_map(
        metadata.get("system"),
        "metadata.system",
        ("build_os", "kernel", "fedora", "arch"),
        errors,
    )
    require_version_map(
        metadata.get("validation_targets"),
        "metadata.validation_targets",
        ("chromium", "firefox", "webkitgtk"),
        errors,
    )
    validate_sha256(benchmark.get("input_sha256"), "benchmark.input_sha256", errors)
    validate_sha256(repro.get("input_sha256"), "reproducibility.input_sha256", errors)
    repro_artifacts = repro.get("artifacts")
    if not isinstance(repro_artifacts, list) or not repro_artifacts:
        errors.append("reproducibility.artifacts must be a non-empty array")
        repro_artifacts = []
    for index, item in enumerate(repro_artifacts):
        path = f"reproducibility.artifacts[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{path} must be an object")
            continue
        require_non_empty_string(item.get("path"), f"{path}.path", errors)
        size = item.get("left_size_bytes")
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            errors.append(f"{path}.left_size_bytes must be a non-negative integer")
        validate_sha256(item.get("left_raw_sha256"), f"{path}.left_raw_sha256", errors)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    benchmark_status = check_status(benchmark)
    reproducibility_status = check_status(repro)
    automated_outcome = combined_status(benchmark_status, reproducibility_status)
    automated_pass = automated_outcome == "PASS"
    candidate_artifacts = [
        {
            "path": item["path"],
            "size_bytes": item["left_size_bytes"],
            "sha256": item["left_raw_sha256"],
        }
        for item in repro_artifacts
    ]
    reproducibility_reference = {
        "input_sha256": repro["input_sha256"],
        "report": {
            "path": str(args.reproducibility),
            "sha256": sha256_file(args.reproducibility),
        },
    }
    automated_checks = [
        {
            "id": "benchmark",
            "status": benchmark_status,
            "input_sha256": benchmark["input_sha256"],
            "report": {
                "path": str(args.benchmark),
                "sha256": sha256_file(args.benchmark),
            },
        },
        {
            "id": "reproducibility",
            "status": reproducibility_status,
            "input_sha256": repro["input_sha256"],
            "report": reproducibility_reference["report"],
        },
    ]
    manifest = {
        "schema_version": 2,
        "attempt_id": metadata["attempt_id"],
        "candidate": {
            "version": "v1.0.0",
            "commit": args.candidate,
            "architecture": "x86_64",
            "clean_tree": metadata["clean_tree"],
            "built_at_utc": metadata["built_at_utc"],
            "build_host": metadata["build_host"],
            "artifacts": candidate_artifacts,
        },
        "toolchains": metadata["toolchains"],
        "system": metadata["system"],
        "reproducibility": reproducibility_reference,
        "validation_targets": metadata["validation_targets"],
        "required_evidence_ids": list(REQUIRED_EVIDENCE_IDS),
        "automated_checks": automated_checks,
        "notice": PUBLICATION_NOTICE,
    }
    manifest_errors = validate_candidate_manifest(manifest)
    if manifest_errors:
        for error in manifest_errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    encoded = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")
    try:
        descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(encoded)
    except FileExistsError:
        print(f"error: immutable RC manifest already exists: {args.output}", file=sys.stderr)
        return 1
    except OSError as error:
        print(f"error: cannot create RC manifest: {error}", file=sys.stderr)
        return 1
    print(f"created immutable RC manifest: {args.output}")
    return 0 if automated_pass else 1


def git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=repo, text=True, capture_output=True, check=False)


def guard(args: argparse.Namespace) -> int:
    if SHA.fullmatch(args.candidate) is None:
        print("error: candidate must be a full 40-character lowercase Git SHA", file=sys.stderr)
        return 1
    resolved = git(args.repo, "rev-parse", "--verify", f"{args.candidate}^{{commit}}")
    if resolved.returncode != 0:
        print("error: candidate is not a commit in the repository", file=sys.stderr)
        return 1
    head = git(args.repo, "rev-parse", "HEAD")
    if head.returncode != 0 or head.stdout.strip() != args.candidate:
        print(f"error: HEAD is after or different from frozen candidate {args.candidate}", file=sys.stderr)
        return 1
    status = git(args.repo, "status", "--porcelain=v1", "--untracked-files=no")
    if status.returncode != 0:
        print(f"error: cannot inspect tracked worktree: {status.stderr.strip()}", file=sys.stderr)
        return 1
    if status.stdout:
        print("error: tracked worktree diff exists after frozen candidate SHA", file=sys.stderr)
        print(status.stdout, file=sys.stderr, end="")
        return 1
    print(f"OK: HEAD and tracked files remain frozen at {args.candidate}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Create external RC evidence or enforce the post-M9 freeze.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    create = subparsers.add_parser("generate")
    create.add_argument("--candidate", required=True)
    create.add_argument("--benchmark", required=True, type=Path)
    create.add_argument("--reproducibility", required=True, type=Path)
    create.add_argument("--metadata", required=True, type=Path)
    create.add_argument("--output", required=True, type=Path)
    create.set_defaults(handler=generate)
    freeze = subparsers.add_parser("guard")
    freeze.add_argument("--candidate", required=True)
    freeze.add_argument("--repo", type=Path, default=Path.cwd())
    freeze.set_defaults(handler=guard)
    args = parser.parse_args()
    return args.handler(args)


if __name__ == "__main__":
    raise SystemExit(main())
