#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

from rc_manifest import validate_candidate_manifest
from release_evidence import candidate_commit, validate_evidence_index
from release_schema import read_object, sha256_file


def validate_technical_readiness(
    candidate: dict[str, Any], index: dict[str, Any], errors: list[str]
) -> None:
    automated_checks = candidate.get("automated_checks")
    if isinstance(automated_checks, list):
        for check_index, check in enumerate(automated_checks):
            if isinstance(check, dict) and check.get("status") != "PASS":
                errors.append(f"automated_checks[{check_index}].status must be PASS")

    if index.get("aggregate_status") != "PASS":
        errors.append("index.aggregate_status must be PASS")
    records = index.get("records")
    if isinstance(records, list):
        for record_index, record in enumerate(records):
            if isinstance(record, dict) and record.get("status") != "PASS":
                errors.append(f"records[{record_index}].status must be PASS")


def git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=repo,
        text=True,
        capture_output=True,
        check=False,
    )


def validate_git_state(repo: Path, frozen_commit: str, errors: list[str]) -> None:
    head = git(repo, "rev-parse", "HEAD")
    if head.returncode != 0:
        errors.append(f"cannot resolve repository HEAD: {head.stderr.strip()}")
    elif frozen_commit and head.stdout.strip() != frozen_commit:
        errors.append("repository HEAD must equal candidate commit")

    status = git(repo, "status", "--porcelain=v1")
    if status.returncode != 0:
        errors.append(f"cannot inspect repository worktree: {status.stderr.strip()}")
    elif status.stdout:
        errors.append("repository worktree must be clean")

    tag = git(repo, "show-ref", "--verify", "--quiet", "refs/tags/v1.0.0")
    if tag.returncode == 0:
        errors.append("refs/tags/v1.0.0 must not exist")
    elif tag.returncode != 1:
        detail = tag.stderr.strip() or f"exit status {tag.returncode}"
        errors.append(f"cannot inspect refs/tags/v1.0.0: {detail}")


def write_report(output: Path, report: dict[str, Any]) -> bool:
    encoded = (json.dumps(report, indent=2, sort_keys=True) + "\n").encode("utf-8")
    try:
        descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(encoded)
    except FileExistsError:
        print(
            f"error: immutable final gate report already exists: {output}",
            file=sys.stderr,
        )
        return False
    except OSError as error:
        print(f"error: cannot create final gate report: {error}", file=sys.stderr)
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create the immutable Formal 1.0 technical release gate report."
    )
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--index", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    try:
        candidate_sha256 = sha256_file(args.candidate)
        evidence_index_sha256 = sha256_file(args.index)
    except OSError as error:
        print(f"error: cannot digest release evidence input: {error}", file=sys.stderr)
        return 1

    errors: list[str] = []
    try:
        candidate = read_object(args.candidate, "candidate manifest")
    except ValueError as error:
        errors.append(str(error))
        candidate = {}
    try:
        index = read_object(args.index, "evidence index")
    except ValueError as error:
        errors.append(str(error))
        index = {}

    errors.extend(validate_candidate_manifest(candidate))
    errors.extend(
        validate_evidence_index(
            candidate,
            index,
            candidate_manifest_path=args.candidate,
            candidate_manifest_sha256=candidate_sha256,
        )
    )
    validate_technical_readiness(candidate, index, errors)
    validate_git_state(args.repo, candidate_commit(candidate), errors)

    report = {
        "schema_version": 1,
        "candidate_sha256": candidate_sha256,
        "evidence_index_sha256": evidence_index_sha256,
        "technical_release_ready": not errors,
        "publication_authorized": False,
        "reasons": errors,
    }
    if not write_report(args.output, report):
        return 1

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"created immutable final gate report: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
