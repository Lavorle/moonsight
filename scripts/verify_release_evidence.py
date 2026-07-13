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


SHA_PATTERN = re.compile(r"[0-9a-f]{40}")


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


def require_non_empty_string(value: Any, path: str, errors: list[str]) -> str:
    if not isinstance(value, str) or not value:
        errors.append(f"{path} must be a non-empty string")
        return ""
    return value


def validate_candidate(
    candidate: dict[str, Any], errors: list[str]
) -> tuple[str, dict[str, str]]:
    if candidate.get("schema_version") != 2:
        errors.append("candidate.schema_version must be 2")

    identity = require_object(candidate.get("candidate"), "candidate", errors)
    commit = require_non_empty_string(
        identity.get("commit"), "candidate.commit", errors
    )
    if commit and SHA_PATTERN.fullmatch(commit) is None:
        errors.append("candidate.commit must be a full lowercase Git SHA")

    artifacts: dict[str, str] = {}
    raw_artifacts = require_array(
        identity.get("artifacts"), "candidate.artifacts", errors
    )
    if not raw_artifacts:
        errors.append("candidate.artifacts must not be empty")
    for index, raw_artifact in enumerate(raw_artifacts):
        path = f"candidate.artifacts[{index}]"
        artifact = require_object(raw_artifact, path, errors)
        artifact_path = require_non_empty_string(
            artifact.get("path"), f"{path}.path", errors
        )
        artifact_digest = validate_sha256(
            artifact.get("sha256"), f"{path}.sha256", errors
        )
        if artifact_path in artifacts:
            errors.append(f"{path}.path duplicates candidate artifact {artifact_path}")
        elif artifact_path and artifact_digest:
            artifacts[artifact_path] = artifact_digest

    if candidate.get("required_evidence_ids") != list(REQUIRED_EVIDENCE_IDS):
        errors.append("candidate.required_evidence_ids must equal the Formal 1.0 matrix")

    automated_checks = require_array(
        candidate.get("automated_checks"), "candidate.automated_checks", errors
    )
    if not automated_checks:
        errors.append("candidate.automated_checks must not be empty")
    for index, raw_check in enumerate(automated_checks):
        path = f"automated_checks[{index}]"
        check = require_object(raw_check, path, errors)
        require_non_empty_string(check.get("id"), f"{path}.id", errors)
        if check.get("status") != "PASS":
            errors.append(f"{path}.status must be PASS")

    return commit, artifacts


def validate_index(
    candidate_path: Path,
    candidate_sha256: str,
    candidate_commit: str,
    candidate_artifacts: dict[str, str],
    index: dict[str, Any],
    errors: list[str],
) -> None:
    if index.get("schema_version") != 1:
        errors.append("index.schema_version must be 1")
    if index.get("candidate_commit") != candidate_commit:
        errors.append("index.candidate_commit must equal candidate commit")

    candidate_reference = require_object(
        index.get("candidate_manifest"), "index.candidate_manifest", errors
    )
    if candidate_reference.get("path") != candidate_path.name:
        errors.append("index.candidate_manifest.path must name the candidate manifest")
    referenced_candidate_digest = validate_sha256(
        candidate_reference.get("sha256"),
        "index.candidate_manifest.sha256",
        errors,
    )
    if (
        referenced_candidate_digest
        and referenced_candidate_digest != candidate_sha256
    ):
        errors.append(
            "index.candidate_manifest.sha256 must equal the candidate manifest"
        )

    if index.get("aggregate_status") != "PASS":
        errors.append("index.aggregate_status must be PASS")

    records = require_array(index.get("records"), "index.records", errors)
    seen: set[str] = set()
    duplicates: set[str] = set()
    for record_index, raw_record in enumerate(records):
        path = f"records[{record_index}]"
        record = require_object(raw_record, path, errors)
        evidence_id = record.get("id")
        if evidence_id not in REQUIRED_EVIDENCE_IDS:
            errors.append(f"{path}.id is not a required evidence ID")
        elif evidence_id in seen:
            duplicates.add(evidence_id)
        else:
            seen.add(evidence_id)

        if record.get("status") != "PASS":
            errors.append(f"{path}.status must be PASS")
        if record.get("candidate_commit") != candidate_commit:
            errors.append(f"{path}.candidate_commit must equal candidate commit")

        artifact = require_object(record.get("artifact"), f"{path}.artifact", errors)
        artifact_path = require_non_empty_string(
            artifact.get("path"), f"{path}.artifact.path", errors
        )
        artifact_digest = validate_sha256(
            artifact.get("sha256"), f"{path}.artifact.sha256", errors
        )
        if artifact_path and artifact_path not in candidate_artifacts:
            errors.append(f"{path}.artifact.path must reference candidate artifact")
        elif (
            artifact_path
            and artifact_digest
            and artifact_digest != candidate_artifacts.get(artifact_path)
        ):
            errors.append(f"{path}.artifact.sha256 must equal candidate artifact")

        require_non_empty_string(record.get("record_path"), f"{path}.record_path", errors)
        for field in (
            "record_sha256",
            "public_evidence_sha256",
            "raw_evidence_sha256",
        ):
            validate_sha256(record.get(field), f"{path}.{field}", errors)

    for evidence_id in sorted(duplicates):
        errors.append(f"duplicate evidence ID: {evidence_id}")
    missing = [
        evidence_id
        for evidence_id in REQUIRED_EVIDENCE_IDS
        if evidence_id not in seen
    ]
    if missing:
        errors.append(f"missing required evidence IDs: {', '.join(missing)}")


def git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=repo,
        text=True,
        capture_output=True,
        check=False,
    )


def validate_git_state(repo: Path, candidate_commit: str, errors: list[str]) -> None:
    head = git(repo, "rev-parse", "HEAD")
    if head.returncode != 0:
        errors.append(f"cannot resolve repository HEAD: {head.stderr.strip()}")
    elif candidate_commit and head.stdout.strip() != candidate_commit:
        errors.append("repository HEAD must equal candidate commit")

    status = git(repo, "status", "--porcelain=v1")
    if status.returncode != 0:
        errors.append(f"cannot inspect repository worktree: {status.stderr.strip()}")
    elif status.stdout:
        errors.append("repository worktree must be clean")

    tag = git(repo, "show-ref", "--verify", "refs/tags/v1.0.0")
    if tag.returncode == 0:
        errors.append("refs/tags/v1.0.0 must not exist")


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

    candidate_commit, candidate_artifacts = validate_candidate(candidate, errors)
    validate_index(
        args.candidate,
        candidate_sha256,
        candidate_commit,
        candidate_artifacts,
        index,
        errors,
    )
    validate_git_state(args.repo, candidate_commit, errors)

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
