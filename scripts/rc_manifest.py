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
        "notice": "Candidate identity does not authorize publication.",
    }
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
