#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


SHA = re.compile(r"^[0-9a-f]{40}$")


def read_json(path: Path, label: str) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read {label}: {error}") from error
    if not isinstance(data, dict):
        raise ValueError(f"{label} must be an object")
    return data


def file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(args: argparse.Namespace) -> int:
    if SHA.fullmatch(args.candidate) is None:
        print("error: candidate must be a full 40-character lowercase Git SHA", file=sys.stderr)
        return 1
    try:
        benchmark = read_json(args.benchmark, "benchmark report")
        repro = read_json(args.reproducibility, "reproducibility report")
        metadata = read_json(args.metadata, "RC metadata")
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    errors: list[str] = []
    for field in ("toolchains", "locks", "environment"):
        if not isinstance(metadata.get(field), dict) or not metadata[field]:
            errors.append(f"metadata.{field} must be a non-empty object")
    if not isinstance(metadata.get("commands"), list) or not metadata["commands"]:
        errors.append("metadata.commands must be a non-empty array")
    if not isinstance(metadata.get("authorized_operator"), str) or not metadata["authorized_operator"]:
        errors.append("metadata.authorized_operator must be a non-empty string")
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    reproducibility_artifacts = [
        {
            "path": item["path"],
            "left_raw_sha256": item["left_raw_sha256"],
            "right_raw_sha256": item["right_raw_sha256"],
            "left_normalized_sha256": item["left_normalized_sha256"],
            "right_normalized_sha256": item["right_normalized_sha256"],
            **({"normalization_id": item["normalization_id"]} if "normalization_id" in item else {}),
        }
        for item in repro.get("artifacts", [])
    ]
    automated_pass = benchmark.get("outcome") == "PASS" and repro.get("outcome") == "PASS"
    candidate_artifacts = [
        {
            "path": item["path"],
            "sha256": item["left_raw_sha256"],
            "normalized_sha256": item["left_normalized_sha256"],
        }
        for item in reproducibility_artifacts
    ]
    manifest = {
        "schema_version": 1,
        "candidate": {
            "commit": args.candidate,
            "toolchains": metadata["toolchains"],
            "locks": metadata["locks"],
            "artifacts": candidate_artifacts,
        },
        "environment": metadata["environment"],
        "commands": metadata["commands"],
        "authorized_operator": metadata["authorized_operator"],
        "evidence_inputs": {
            "benchmark": {"path": str(args.benchmark), "sha256": file_digest(args.benchmark)},
            "reproducibility": {"path": str(args.reproducibility), "sha256": file_digest(args.reproducibility)},
        },
        "artifact_digests": reproducibility_artifacts,
        "generated_files": metadata.get("generated_files", []),
        "automated_checks": [
            {
                "name": "Formal 1.0 benchmark gates",
                "status": "PASS" if benchmark.get("outcome") == "PASS" else "FAIL",
                "commit": args.candidate,
                "output": str(args.benchmark),
            },
            {
                "name": "two-build package reproducibility",
                "status": "PASS" if repro.get("outcome") == "PASS" else "FAIL",
                "commit": args.candidate,
                "output": str(args.reproducibility),
            },
        ],
        "automated_outcome": "PASS" if automated_pass else "FAIL",
        "external_checks": {
            name: {"status": "NOT_RUN", "commit": args.candidate, "artifacts": []}
            for name in ("W1", "D1", "C1")
        },
        "release_authorized": False,
        "notice": "Automated local evidence does not authorize W1, D1, C1, tagging, publication, or release.",
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
