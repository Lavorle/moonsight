#!/usr/bin/env python3
"""Draft-first GitHub release publisher for MoonSight Formal 1.0.

Default mode is dry-run (print planned argv arrays, no mutations).
Execute mode requires both --execute and --authorize v1.0.0.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from release_schema import read_object, sha256_file

VERSION = "v1.0.0"
TAG_MESSAGE = "MoonSight v1.0.0"
RELEASE_TITLE = "MoonSight v1.0.0"

METADATA_ATTACHMENT_NAMES = (
    "SHA256SUMS",
    "candidate.json",
    "evidence-index.json",
    "final-gate.json",
    "notes.md",
)


def run_command(
    argv: list[str],
    *,
    cwd: Path | None = None,
    check: bool = False,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        text=True,
        capture_output=True,
        check=check,
    )


def die(message: str, code: int = 1) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(code)


def git_argv(repo: Path, *args: str) -> list[str]:
    return ["git", "-C", str(repo), *args]


def load_inputs(
    candidate_path: Path,
    index_path: Path,
    gate_path: Path,
    artifacts_dir: Path,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], list[str]]:
    candidate = read_object(candidate_path, "candidate")
    index = read_object(index_path, "index")
    gate = read_object(gate_path, "gate")

    candidate_block = candidate.get("candidate")
    if not isinstance(candidate_block, dict):
        die("candidate.candidate must be an object")
    artifacts = candidate_block.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        die("candidate.candidate.artifacts must be a non-empty list")

    artifact_names: list[str] = []
    for index_item, item in enumerate(artifacts):
        if not isinstance(item, dict) or not isinstance(item.get("path"), str):
            die(f"candidate.candidate.artifacts[{index_item}].path must be a string")
        artifact_names.append(item["path"])

    for name in artifact_names + ["SHA256SUMS"]:
        path = artifacts_dir / name
        if not path.is_file():
            die(f"missing artifact file: {path}")

    return candidate, index, gate, artifact_names


def required_attachment_names(artifact_names: list[str]) -> list[str]:
    return list(artifact_names) + list(METADATA_ATTACHMENT_NAMES)


def stage_metadata_files(
    *,
    staging_dir: Path,
    artifacts_dir: Path,
    candidate_path: Path,
    index_path: Path,
    gate_path: Path,
    notes_path: Path,
    artifact_names: list[str],
) -> dict[str, Path]:
    """Copy/link every attachment into staging_dir under its release asset name."""
    staging_dir.mkdir(parents=True, exist_ok=True)
    mapping: dict[str, Path] = {}

    for name in artifact_names:
        source = artifacts_dir / name
        dest = staging_dir / name
        if dest.resolve() != source.resolve():
            shutil.copy2(source, dest)
        mapping[name] = dest

    pairs = {
        "SHA256SUMS": artifacts_dir / "SHA256SUMS",
        "candidate.json": candidate_path,
        "evidence-index.json": index_path,
        "final-gate.json": gate_path,
        "notes.md": notes_path,
    }
    for name, source in pairs.items():
        if not source.is_file():
            die(f"missing metadata file: {source}")
        dest = staging_dir / name
        if dest.resolve() != source.resolve():
            shutil.copy2(source, dest)
        mapping[name] = dest
    return mapping


def plan_commands(
    *,
    repo: Path,
    candidate_path: Path,
    index_path: Path,
    gate_path: Path,
    artifacts_dir: Path,
    notes_path: Path,
) -> dict[str, Any]:
    candidate, _index, gate, artifact_names = load_inputs(
        candidate_path, index_path, gate_path, artifacts_dir
    )
    candidate_block = candidate["candidate"]
    commit = candidate_block["commit"]
    if candidate_block.get("version") != VERSION:
        die("candidate.version must be v1.0.0")
    if not gate.get("technical_release_ready"):
        die("technical_release_ready is false")
    if not notes_path.is_file():
        die(f"missing notes file: {notes_path}")

    # Dry-run lists concrete local paths without copying/mutating the worktree.
    path_by_name: dict[str, Path] = {
        name: artifacts_dir / name for name in artifact_names
    }
    path_by_name["SHA256SUMS"] = artifacts_dir / "SHA256SUMS"
    path_by_name["candidate.json"] = candidate_path
    path_by_name["evidence-index.json"] = index_path
    path_by_name["final-gate.json"] = gate_path
    path_by_name["notes.md"] = notes_path
    required = required_attachment_names(artifact_names)
    attachment_paths = [str(path_by_name[name]) for name in required]

    commands: list[dict[str, Any]] = [
        {
            "phase": "tag",
            "argv": git_argv(repo, "tag", "-a", VERSION, commit, "-m", TAG_MESSAGE),
        },
        {
            "phase": "push-tag",
            "argv": git_argv(repo, "push", "origin", f"refs/tags/{VERSION}"),
        },
        {
            "phase": "create-draft",
            "argv": [
                "gh",
                "release",
                "create",
                VERSION,
                "--draft",
                "--title",
                RELEASE_TITLE,
                "--notes-file",
                str(notes_path),
            ],
        },
        {
            "phase": "upload",
            "argv": [
                "gh",
                "release",
                "upload",
                VERSION,
                *attachment_paths,
            ],
        },

        {
            "phase": "view-assets",
            "argv": [
                "gh",
                "release",
                "view",
                VERSION,
                "--json",
                "assets,isDraft,tagName",
            ],
        },
        {
            "phase": "download-verify",
            "argv": [
                "gh",
                "release",
                "download",
                VERSION,
                "--dir",
                str(artifacts_dir / ".publish-verify"),
                "--pattern",
                "*",
            ],
        },
        {
            "phase": "publish",
            "argv": ["gh", "release", "edit", VERSION, "--draft=false"],
        },
    ]
    return {
        "mode": "plan",
        "version": VERSION,
        "commit": commit,
        "attachments": required_attachment_names(artifact_names),
        "commands": commands,
    }


def preflight_execute(
    repo: Path,
    candidate: dict[str, Any],
    gate: dict[str, Any],
) -> None:
    if not gate.get("technical_release_ready"):
        die("technical_release_ready is false")

    commit = candidate["candidate"]["commit"]
    if not isinstance(commit, str) or not commit:
        die("candidate.candidate.commit must be a non-empty string")

    head = run_command(git_argv(repo, "rev-parse", "HEAD"))
    if head.returncode != 0:
        die(f"cannot resolve repository HEAD: {head.stderr.strip()}")
    if head.stdout.strip() != commit:
        die("HEAD must equal candidate commit")

    status = run_command(git_argv(repo, "status", "--porcelain=v1"))
    if status.returncode != 0:
        die(f"cannot inspect repository worktree: {status.stderr.strip()}")
    if status.stdout.strip():
        die("worktree must be clean")

    auth = run_command(["gh", "auth", "status"], cwd=repo)
    if auth.returncode != 0:
        detail = auth.stderr.strip() or auth.stdout.strip() or "gh auth status failed"
        die(f"gh auth status failed: {detail}")


def peel_local_tag(repo: Path) -> str | None:
    """Return peeled commit SHA for local annotated/lightweight tag, or None if absent."""
    exists = run_command(
        git_argv(repo, "show-ref", "--verify", "--quiet", f"refs/tags/{VERSION}")
    )
    if exists.returncode == 1:
        return None
    if exists.returncode != 0:
        die(f"cannot inspect local tag {VERSION}: {exists.stderr.strip()}")

    peeled = run_command(git_argv(repo, "rev-parse", f"{VERSION}^{{}}"))
    if peeled.returncode != 0:
        # Lightweight tag: rev-parse VERSION
        plain = run_command(git_argv(repo, "rev-parse", VERSION))
        if plain.returncode != 0:
            die(f"cannot peel local tag {VERSION}: {peeled.stderr.strip()}")
        return plain.stdout.strip()
    return peeled.stdout.strip()


def peel_remote_tag(repo: Path) -> str | None:
    """Return peeled commit for origin refs/tags/VERSION, or None if absent."""
    result = run_command(
        git_argv(
            repo,
            "ls-remote",
            "origin",
            f"refs/tags/{VERSION}",
            f"refs/tags/{VERSION}^{{}}",
        )
    )
    if result.returncode != 0:
        die(f"cannot inspect remote tag {VERSION}: {result.stderr.strip()}")

    peeled: str | None = None
    plain: str | None = None
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        sha, ref = parts[0], parts[1]
        if ref.endswith("^{}"):
            peeled = sha
        else:
            plain = sha
    return peeled or plain


def ensure_tag(repo: Path, commit: str) -> None:
    local_sha = peel_local_tag(repo)
    if local_sha is None:
        created = run_command(
            git_argv(repo, "tag", "-a", VERSION, commit, "-m", TAG_MESSAGE),
            cwd=repo,
        )
        if created.returncode != 0:
            die(f"failed to create annotated tag {VERSION}: {created.stderr.strip()}")
        local_sha = peel_local_tag(repo)
        if local_sha is None:
            die(f"tag {VERSION} missing after create")
    if local_sha != commit:
        die(
            f"local tag {VERSION} peels to {local_sha}, expected candidate {commit}; "
            "stop for human decision"
        )

    remote_sha = peel_remote_tag(repo)
    if remote_sha is None:
        pushed = run_command(
            git_argv(repo, "push", "origin", f"refs/tags/{VERSION}"),
            cwd=repo,
        )
        if pushed.returncode != 0:
            die(f"failed to push tag {VERSION}: {pushed.stderr.strip()}")
        remote_sha = peel_remote_tag(repo)
        if remote_sha is None:
            die(f"remote tag {VERSION} missing after push")
    if remote_sha != commit:
        die(
            f"remote tag {VERSION} peels to {remote_sha}, expected candidate {commit}; "
            "stop for human decision"
        )


def release_view(repo: Path) -> dict[str, Any] | None:
    result = run_command(
        ["gh", "release", "view", VERSION, "--json", "assets,isDraft,tagName"],
        cwd=repo,
    )
    if result.returncode != 0:
        return None
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        die(f"cannot parse gh release view output: {error}")
    if not isinstance(data, dict):
        die("gh release view output must be an object")
    return data


def asset_names(view: dict[str, Any]) -> set[str]:
    assets = view.get("assets")
    if not isinstance(assets, list):
        return set()
    names: set[str] = set()
    for item in assets:
        if isinstance(item, dict) and isinstance(item.get("name"), str):
            names.add(item["name"])
    return names


def ensure_draft_release(repo: Path, notes_path: Path) -> dict[str, Any]:
    view = release_view(repo)
    if view is None:
        created = run_command(
            [
                "gh",
                "release",
                "create",
                VERSION,
                "--draft",
                "--title",
                RELEASE_TITLE,
                "--notes-file",
                str(notes_path),
            ],
            cwd=repo,
        )
        if created.returncode != 0:
            die(f"failed to create draft release: {created.stderr.strip()}")
        view = release_view(repo)
        if view is None:
            die("draft release missing after create")
    if view.get("isDraft") is not True:
        die(f"release {VERSION} exists but is not a draft; stop for human decision")
    return view


def ensure_attachments(
    repo: Path,
    staged: dict[str, Path],
    required: list[str],
) -> None:
    view = release_view(repo)
    if view is None:
        die("release missing while uploading attachments")
    present = asset_names(view)
    missing = [name for name in required if name not in present]
    if not missing:
        return
    paths = [str(staged[name]) for name in missing]
    uploaded = run_command(
        ["gh", "release", "upload", VERSION, *paths],
        cwd=repo,
    )
    if uploaded.returncode != 0:
        die(f"failed to upload attachments: {uploaded.stderr.strip()}")


def verify_remote_attachments(
    repo: Path,
    staged: dict[str, Path],
    required: list[str],
) -> None:
    view = release_view(repo)
    if view is None:
        die("release missing during attachment verification")
    if view.get("isDraft") is not True:
        die(f"release {VERSION} is not a draft during verification; refuse publish")

    present = asset_names(view)
    missing = [name for name in required if name not in present]
    if missing:
        die(f"incomplete remote attachments: {', '.join(missing)}")
    extra = sorted(present - set(required))
    # Extra assets are allowed but required set must be complete.
    _ = extra

    with tempfile.TemporaryDirectory(prefix="moonsight-publish-verify-") as tmp:
        download_dir = Path(tmp)
        downloaded = run_command(
            [
                "gh",
                "release",
                "download",
                VERSION,
                "--dir",
                str(download_dir),
                "--pattern",
                "*",
            ],
            cwd=repo,
        )
        if downloaded.returncode != 0:
            die(f"failed to download release assets: {downloaded.stderr.strip()}")

        for name in required:
            remote_path = download_dir / name
            if not remote_path.is_file():
                die(f"downloaded asset missing: {name}")
            local_path = staged[name]
            local_digest = sha256_file(local_path)
            remote_digest = sha256_file(remote_path)
            if local_digest != remote_digest:
                die(
                    f"SHA-256 mismatch for {name}: "
                    f"local={local_digest} remote={remote_digest}"
                )


def final_publish_checks(repo: Path, commit: str, required: list[str]) -> None:
    remote_sha = peel_remote_tag(repo)
    if remote_sha is None:
        die(f"remote tag {VERSION} missing immediately before publish")
    if remote_sha != commit:
        die(
            f"remote tag {VERSION} peels to {remote_sha}, expected {commit}; "
            "refuse publish"
        )

    view = release_view(repo)
    if view is None:
        die("release missing immediately before publish")
    if view.get("isDraft") is not True:
        die(f"release {VERSION} is not a draft immediately before publish")
    present = asset_names(view)
    missing = [name for name in required if name not in present]
    if missing:
        die(f"incomplete remote attachments before publish: {', '.join(missing)}")


def execute_publish(
    *,
    repo: Path,
    candidate_path: Path,
    index_path: Path,
    gate_path: Path,
    artifacts_dir: Path,
    notes_path: Path,
) -> None:
    candidate, _index, gate, artifact_names = load_inputs(
        candidate_path, index_path, gate_path, artifacts_dir
    )
    if candidate["candidate"].get("version") != VERSION:
        die("candidate.version must be v1.0.0")
    commit = candidate["candidate"]["commit"]
    if not isinstance(commit, str):
        die("candidate.candidate.commit must be a string")

    preflight_execute(repo, candidate, gate)

    required = required_attachment_names(artifact_names)
    with tempfile.TemporaryDirectory(prefix="moonsight-publish-stage-") as tmp:
        staging = Path(tmp)
        staged = stage_metadata_files(
            staging_dir=staging,
            artifacts_dir=artifacts_dir,
            candidate_path=candidate_path,
            index_path=index_path,
            gate_path=gate_path,
            notes_path=notes_path,
            artifact_names=artifact_names,
        )

        ensure_tag(repo, commit)
        ensure_draft_release(repo, staged["notes.md"])
        ensure_attachments(repo, staged, required)
        verify_remote_attachments(repo, staged, required)
        final_publish_checks(repo, commit, required)

        published = run_command(
            ["gh", "release", "edit", VERSION, "--draft=false"],
            cwd=repo,
        )
        if published.returncode != 0:
            die(f"failed to publish release: {published.stderr.strip()}")


def run(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Draft-first GitHub release publisher for MoonSight Formal 1.0"
    )
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--index", type=Path, required=True)
    parser.add_argument("--gate", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--notes", type=Path, required=True)
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Perform real mutations (requires --authorize v1.0.0)",
    )
    parser.add_argument(
        "--authorize",
        default="",
        help="Must be exactly v1.0.0 together with --execute",
    )
    args = parser.parse_args(argv)

    try:
        if not args.execute:
            plan = plan_commands(
                repo=args.repo,
                candidate_path=args.candidate,
                index_path=args.index,
                gate_path=args.gate,
                artifacts_dir=args.artifacts,
                notes_path=args.notes,
            )
            print(
                json.dumps(
                    {
                        "mode": "dry-run",
                        "version": plan["version"],
                        "commit": plan["commit"],
                        "attachments": plan["attachments"],
                        "commands": plan["commands"],
                    },
                    indent=2,
                    sort_keys=True,
                )
            )
            return 0

        if args.authorize != VERSION:
            print(
                "error: explicit --authorize v1.0.0 required",
                file=sys.stderr,
            )
            return 2

        execute_publish(
            repo=args.repo,
            candidate_path=args.candidate,
            index_path=args.index,
            gate_path=args.gate,
            artifacts_dir=args.artifacts,
            notes_path=args.notes,
        )
        print(f"published GitHub release {VERSION}")
        return 0
    except SystemExit as error:
        # die() raises SystemExit(message code); argparse also uses SystemExit.
        code = error.code
        if code is None:
            return 0
        if isinstance(code, int):
            return code
        # SystemExit with string message
        print(f"error: {code}", file=sys.stderr)
        return 1
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


def main() -> int:
    return run()


if __name__ == "__main__":
    raise SystemExit(main())
