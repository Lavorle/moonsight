from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

from release_schema import REQUIRED_EVIDENCE_IDS  # noqa: E402
import publish_github_release as publisher  # noqa: E402


VERSION = "v1.0.0"
WEB = "moonsight-web-x86_64-v1.0.0.zip"
APPIMAGE = "moonsight-linux-x86_64-v1.0.0.AppImage"
DEB = "moonsight-linux-x86_64-v1.0.0.deb"
RPM = "moonsight-linux-x86_64-v1.0.0.rpm"
ARTIFACTS = (WEB, APPIMAGE, DEB, RPM)
METADATA_NAMES = (
    "SHA256SUMS",
    "candidate.json",
    "evidence-index.json",
    "final-gate.json",
    "notes.md",
)
ALL_ATTACHMENTS = ARTIFACTS + METADATA_NAMES


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args], cwd=repo, text=True, capture_output=True, check=False
    )


def init_repo(root: Path) -> tuple[Path, str]:
    repo = root / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    subprocess.run(
        ["git", "config", "user.email", "release-test@example.invalid"],
        cwd=repo,
        check=True,
    )
    subprocess.run(
        ["git", "config", "user.name", "Release Test"], cwd=repo, check=True
    )
    (repo / "README").write_text("candidate\n", encoding="utf-8")
    subprocess.run(["git", "add", "."], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-qm", "candidate"], cwd=repo, check=True)
    commit = git(repo, "rev-parse", "HEAD").stdout.strip()
    return repo, commit


def make_fixture(root: Path) -> dict[str, Path | str]:
    repo, commit = init_repo(root)
    artifacts = root / "artifacts"
    artifacts.mkdir()
    digests: dict[str, str] = {}
    for name in ARTIFACTS:
        data = f"payload-{name}\n".encode()
        (artifacts / name).write_bytes(data)
        digests[name] = sha256_bytes(data)
    (artifacts / "SHA256SUMS").write_text(
        "\n".join(f"{digests[n]}  {n}" for n in ARTIFACTS) + "\n", encoding="utf-8"
    )
    candidate = {
        "schema_version": 2,
        "attempt_id": "rc-test-1",
        "candidate": {
            "version": VERSION,
            "commit": commit,
            "architecture": "x86_64",
            "clean_tree": True,
            "built_at_utc": "2026-07-13T03:00:00Z",
            "build_host": "test",
            "artifacts": [
                {
                    "path": n,
                    "size_bytes": (artifacts / n).stat().st_size,
                    "sha256": digests[n],
                }
                for n in ARTIFACTS
            ],
        },
        "toolchains": {
            "moon": "0.0.0",
            "node": "0.0.0",
            "rustc": "0.0.0",
            "tauri_cli": "0.0.0",
        },
        "system": {"ubuntu": "24.04", "fedora": "42", "arch": "2026-07-13"},
        "automated_checks": [
            {"id": "benchmark", "status": "PASS"},
            {"id": "reproducibility", "status": "PASS"},
        ],
        "publication_notice": "Candidate identity does not authorize publication.",
    }
    candidate_path = root / "candidate.json"
    write_json(candidate_path, candidate)
    records = []
    for evidence_id in REQUIRED_EVIDENCE_IDS:
        art = WEB if evidence_id.startswith("W1") or evidence_id == "C1-web" else APPIMAGE
        if evidence_id.endswith("-deb"):
            art = DEB
        if evidence_id.endswith("-rpm"):
            art = RPM
        records.append(
            {
                "schema_version": 1,
                "id": evidence_id,
                "status": "PASS",
                "candidate_commit": commit,
                "artifact": {"path": art, "sha256": digests[art]},
                "tester": "fixture",
                "timestamp_utc": "2026-07-13T04:00:00Z",
                "environment": {
                    "os": "Ubuntu",
                    "os_version": "24.04",
                    "browser_or_shell": "chromium",
                    "gpu": "test",
                    "driver": "test",
                },
                "executed_steps": [
                    {"order": 1, "description": "play", "result": "PASS"}
                ],
                "attachments": {"logs": ["log.txt"], "visuals": ["shot.png"]},
                "redacted_inspection": {"saves": "ok"},
                "redaction_statement": "synthetic fixture only",
                "public_evidence_sha256": "b" * 64,
                "raw_evidence_sha256": "c" * 64,
            }
        )
    records_dir = root / "records"
    records_dir.mkdir()
    for record in records:
        write_json(records_dir / f"{record['id']}.json", record)
    index = {
        "schema_version": 1,
        "candidate_commit": commit,
        "aggregate_status": "PASS",
        "records": records,
    }
    index_path = root / "index.json"
    write_json(index_path, index)
    gate = {
        "schema_version": 1,
        "candidate_sha256": sha256_bytes(candidate_path.read_bytes()),
        "evidence_index_sha256": sha256_bytes(index_path.read_bytes()),
        "technical_release_ready": True,
        "publication_authorized": False,
        "reasons": [],
    }
    gate_path = root / "gate.json"
    write_json(gate_path, gate)
    notes = root / "notes.md"
    notes.write_text("# MoonSight v1.0.0\n", encoding="utf-8")
    return {
        "repo": repo,
        "commit": commit,
        "candidate": candidate_path,
        "index": index_path,
        "gate": gate_path,
        "artifacts": artifacts,
        "notes": notes,
    }


def cli_args(fx: dict[str, Path | str], *extra: str) -> list[str]:
    return [
        "--repo",
        str(fx["repo"]),
        "--candidate",
        str(fx["candidate"]),
        "--index",
        str(fx["index"]),
        "--gate",
        str(fx["gate"]),
        "--artifacts",
        str(fx["artifacts"]),
        "--notes",
        str(fx["notes"]),
        *extra,
    ]


def local_sources(fx: dict[str, Path | str]) -> dict[str, Path]:
    artifacts = Path(fx["artifacts"])
    return {
        WEB: artifacts / WEB,
        APPIMAGE: artifacts / APPIMAGE,
        DEB: artifacts / DEB,
        RPM: artifacts / RPM,
        "SHA256SUMS": artifacts / "SHA256SUMS",
        "candidate.json": Path(fx["candidate"]),
        "evidence-index.json": Path(fx["index"]),
        "final-gate.json": Path(fx["gate"]),
        "notes.md": Path(fx["notes"]),
    }


def extract_download_dir(argv: list[str]) -> Path | None:
    if "--dir" in argv:
        return Path(argv[argv.index("--dir") + 1])
    for item in argv:
        if item.startswith("--dir="):
            return Path(item.split("=", 1)[1])
    return None


def make_fake_run(
    fx: dict[str, Path | str],
    *,
    release_exists: bool = False,
    remote_assets: list[str] | None = None,
    remote_tag_sha: str | None = None,
    local_tag_sha: str | None = None,
    corrupt_download: str | None = None,
    fail_auth: bool = False,
) -> Any:
    """Build a run_command double for execute-path tests."""
    sources = local_sources(fx)
    commit = str(fx["commit"])
    state = {
        "release_exists": release_exists,
        "assets": list(remote_assets if remote_assets is not None else []),
        "remote_tag": remote_tag_sha,
        "local_tag": local_tag_sha,
    }
    calls: list[list[str]] = []

    def fake_run(
        argv: list[str], **kwargs: Any
    ) -> subprocess.CompletedProcess[str]:
        calls.append(list(argv))
        cwd = kwargs.get("cwd")

        # Prefer real git for local repo mutations when they hit the fixture repo.
        if argv and argv[0] == "git":
            # Normalize git -C repo ... forms.
            if len(argv) >= 3 and argv[1] == "-C":
                git_cwd = Path(argv[2])
                git_args = argv[3:]
            else:
                git_cwd = Path(cwd) if cwd is not None else Path(fx["repo"])
                git_args = argv[1:]

            # Remote tag inspection via ls-remote
            if git_args[:1] == ["ls-remote"] or (
                len(git_args) >= 2 and git_args[0] == "ls-remote"
            ):
                if state["remote_tag"]:
                    # refs/tags/v1.0.0^{} peel line for annotated tags
                    body = (
                        f"{state['remote_tag']}\trefs/tags/{VERSION}\n"
                        f"{state['remote_tag']}\trefs/tags/{VERSION}^{{}}\n"
                    )
                    return subprocess.CompletedProcess(argv, 0, body, "")
                return subprocess.CompletedProcess(argv, 0, "", "")

            # Push tag: mark remote present
            if git_args[:1] == ["push"] or (
                len(git_args) >= 1 and git_args[0] == "push"
            ):
                state["remote_tag"] = commit
                return subprocess.CompletedProcess(argv, 0, "", "")

            # Tag create: track local presence
            if git_args[:2] == ["tag", "-a"] or (
                len(git_args) >= 2 and git_args[0] == "tag" and git_args[1] == "-a"
            ):
                result = subprocess.run(
                    ["git", *git_args],
                    cwd=git_cwd,
                    text=True,
                    capture_output=True,
                    check=False,
                )
                if result.returncode == 0:
                    state["local_tag"] = commit
                return subprocess.CompletedProcess(
                    argv, result.returncode, result.stdout, result.stderr
                )

            # Peel / rev-parse tag
            joined = " ".join(git_args)
            if "rev-parse" in git_args and (
                VERSION in joined or f"refs/tags/{VERSION}" in joined
            ):
                # If real local tag exists, use it; else use state.
                real = subprocess.run(
                    ["git", *git_args],
                    cwd=git_cwd,
                    text=True,
                    capture_output=True,
                    check=False,
                )
                if real.returncode == 0 and real.stdout.strip():
                    return subprocess.CompletedProcess(
                        argv, 0, real.stdout, real.stderr
                    )
                if state["local_tag"]:
                    return subprocess.CompletedProcess(
                        argv, 0, state["local_tag"] + "\n", ""
                    )
                return subprocess.CompletedProcess(argv, 128, "", "not found")

            # show-ref for local tag existence
            if git_args[:1] == ["show-ref"] or "show-ref" in git_args:
                real = subprocess.run(
                    ["git", *git_args],
                    cwd=git_cwd,
                    text=True,
                    capture_output=True,
                    check=False,
                )
                if real.returncode == 0:
                    return subprocess.CompletedProcess(
                        argv, 0, real.stdout, real.stderr
                    )
                if state["local_tag"] and VERSION in joined:
                    return subprocess.CompletedProcess(
                        argv, 0, f"{state['local_tag']} refs/tags/{VERSION}\n", ""
                    )
                return subprocess.CompletedProcess(argv, 1, "", "")

            # Default: real git against fixture repo
            result = subprocess.run(
                ["git", *git_args],
                cwd=git_cwd,
                text=True,
                capture_output=True,
                check=False,
            )
            return subprocess.CompletedProcess(
                argv, result.returncode, result.stdout, result.stderr
            )

        if argv[:2] == ["gh", "auth"]:
            if fail_auth:
                return subprocess.CompletedProcess(argv, 1, "", "not logged in")
            return subprocess.CompletedProcess(argv, 0, "ok", "")

        if argv[:3] == ["gh", "release", "view"]:
            if not state["release_exists"]:
                return subprocess.CompletedProcess(argv, 1, "", "release not found")
            body = json.dumps(
                {
                    "isDraft": True,
                    "tagName": VERSION,
                    "assets": [{"name": n} for n in state["assets"]],
                }
            )
            return subprocess.CompletedProcess(argv, 0, body, "")

        if argv[:3] == ["gh", "release", "create"]:
            state["release_exists"] = True
            # create may include asset paths as trailing args
            for item in argv[3:]:
                path = Path(item)
                if path.is_file():
                    state["assets"].append(path.name)
            return subprocess.CompletedProcess(argv, 0, "", "")

        if argv[:3] == ["gh", "release", "upload"]:
            for item in argv[3:]:
                path = Path(item)
                if path.is_file() and path.name not in state["assets"]:
                    state["assets"].append(path.name)
            return subprocess.CompletedProcess(argv, 0, "", "")

        if argv[:3] == ["gh", "release", "download"]:
            out_dir = extract_download_dir(argv)
            if out_dir is None:
                out_dir = Path(cwd) if cwd is not None else Path(".")
            out_dir.mkdir(parents=True, exist_ok=True)
            for name in state["assets"]:
                if name not in sources:
                    continue
                dest = out_dir / name
                if corrupt_download == name:
                    dest.write_bytes(b"CORRUPT\n")
                else:
                    shutil.copy2(sources[name], dest)
            return subprocess.CompletedProcess(argv, 0, "", "")

        if argv[:3] == ["gh", "release", "edit"]:
            return subprocess.CompletedProcess(argv, 0, "", "")

        return subprocess.CompletedProcess(argv, 0, "", "")

    fake_run.calls = calls  # type: ignore[attr-defined]
    fake_run.state = state  # type: ignore[attr-defined]
    return fake_run


class PublishPlannerTests(unittest.TestCase):
    def test_dry_run_emits_commands_without_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fx = make_fixture(root)
            plan = publisher.plan_commands(
                repo=Path(fx["repo"]),
                candidate_path=Path(fx["candidate"]),
                index_path=Path(fx["index"]),
                gate_path=Path(fx["gate"]),
                artifacts_dir=Path(fx["artifacts"]),
                notes_path=Path(fx["notes"]),
            )
            argv_lists = [c["argv"] for c in plan["commands"]]
            self.assertTrue(any(a[:3] == ["git", "tag", "-a"] or (
                len(a) >= 5 and a[0] == "git" and a[1] == "-C" and a[3:5] == ["tag", "-a"]
            ) or (len(a) >= 3 and "tag" in a and "-a" in a) for a in argv_lists))
            self.assertTrue(
                any(
                    a[:3] == ["gh", "release", "create"]
                    or (len(a) >= 3 and a[0:2] == ["gh", "release"] and "create" in a)
                    for a in argv_lists
                )
            )
            last = argv_lists[-1]
            self.assertEqual(last[:3], ["gh", "release", "edit"])
            self.assertIn("--draft=false", last)
            self.assertNotEqual(
                git(Path(fx["repo"]), "show-ref", "--verify", "refs/tags/v1.0.0").returncode,
                0,
            )

    def test_dry_run_cli_prints_json_plan(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fx = make_fixture(root)
            # Capture stdout via run returning 0 and printing
            from io import StringIO

            buf = StringIO()
            with patch("sys.stdout", buf):
                code = publisher.run(cli_args(fx))
            self.assertEqual(code, 0)
            payload = json.loads(buf.getvalue())
            self.assertEqual(payload["mode"], "dry-run")
            self.assertIsInstance(payload["commands"], list)
            last = payload["commands"][-1]["argv"]
            self.assertEqual(last[:3], ["gh", "release", "edit"])
            self.assertIn("--draft=false", last)

    def test_execute_requires_authorize_v1(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fx = make_fixture(root)
            code = publisher.run(cli_args(fx, "--execute"))
            self.assertNotEqual(code, 0)

    def test_execute_refuses_wrong_authorize_string(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fx = make_fixture(root)
            code = publisher.run(cli_args(fx, "--execute", "--authorize", "v1.0.1"))
            self.assertNotEqual(code, 0)

    def test_execute_refuses_when_gate_not_ready(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fx = make_fixture(root)
            gate = json.loads(Path(fx["gate"]).read_text(encoding="utf-8"))
            gate["technical_release_ready"] = False
            gate["reasons"] = ["synthetic block"]
            write_json(Path(fx["gate"]), gate)
            code = publisher.run(
                cli_args(fx, "--execute", "--authorize", "v1.0.0")
            )
            self.assertNotEqual(code, 0)

    def test_publication_authorized_false_is_ignored(self) -> None:
        """Gate publication_authorized must remain operator-driven via --authorize."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fx = make_fixture(root)
            gate = json.loads(Path(fx["gate"]).read_text(encoding="utf-8"))
            gate["publication_authorized"] = True
            write_json(Path(fx["gate"]), gate)
            # Still needs explicit --authorize; execute alone fails.
            code = publisher.run(cli_args(fx, "--execute"))
            self.assertNotEqual(code, 0)

    def test_execute_sequence_is_tag_then_draft_then_upload_then_verify_then_publish(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fx = make_fixture(root)
            fake = make_fake_run(fx)

            with patch.object(publisher, "run_command", side_effect=fake):
                code = publisher.run(
                    cli_args(fx, "--execute", "--authorize", "v1.0.0")
                )
            self.assertEqual(code, 0, msg=f"calls={fake.calls}")
            calls = fake.calls

            def find(pred: Any) -> int:
                for i, a in enumerate(calls):
                    if pred(a):
                        return i
                raise AssertionError(f"no matching call in {calls}")

            tag_i = find(
                lambda a: (
                    a[:3] == ["git", "tag", "-a"]
                    or (
                        len(a) >= 5
                        and a[0] == "git"
                        and a[1] == "-C"
                        and a[3:5] == ["tag", "-a"]
                    )
                    or (a[0] == "git" and "tag" in a and "-a" in a)
                )
            )
            create_i = find(lambda a: a[:3] == ["gh", "release", "create"])
            publish_i = find(
                lambda a: a[:3] == ["gh", "release", "edit"] and "--draft=false" in a
            )
            self.assertLess(tag_i, create_i)
            self.assertLess(create_i, publish_i)
            # publish is the last mutating gh/git command of interest
            later_mutators = [
                a
                for a in calls[publish_i + 1 :]
                if a[:3]
                in {
                    ("git", "tag", "-a"),
                    ("gh", "release", "create"),
                    ("gh", "release", "upload"),
                    ("gh", "release", "edit"),
                }
                or (a[0] == "git" and "push" in a)
            ]
            self.assertEqual(later_mutators, [])

    def test_execute_refuses_conflicting_local_tag_sha(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fx = make_fixture(root)
            repo = Path(fx["repo"])
            # Create a second commit and tag it as v1.0.0 (wrong SHA).
            (repo / "README").write_text("other\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-qm", "other"], cwd=repo, check=True)
            other = git(repo, "rev-parse", "HEAD").stdout.strip()
            subprocess.run(
                ["git", "tag", "-a", VERSION, other, "-m", "wrong"],
                cwd=repo,
                check=True,
            )
            # Reset HEAD back to candidate so preflight HEAD check can pass.
            candidate = str(fx["commit"])
            subprocess.run(["git", "reset", "--hard", candidate], cwd=repo, check=True)

            fake = make_fake_run(fx, local_tag_sha=other)
            with patch.object(publisher, "run_command", side_effect=fake):
                code = publisher.run(
                    cli_args(fx, "--execute", "--authorize", "v1.0.0")
                )
            self.assertNotEqual(code, 0)
            # Must not publish on conflict
            self.assertFalse(
                any(
                    a[:3] == ["gh", "release", "edit"] and "--draft=false" in a
                    for a in fake.calls
                )
            )

    def test_execute_refuses_incomplete_remote_attachments(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fx = make_fixture(root)
            # Pretend draft already exists with only partial assets; upload disabled
            # by returning assets that stay incomplete (no upload success for missing).
            fake = make_fake_run(
                fx,
                release_exists=True,
                remote_assets=[WEB],  # incomplete
                remote_tag_sha=str(fx["commit"]),
                local_tag_sha=str(fx["commit"]),
            )
            # Pre-create local tag so tag phase is a no-op peel success
            repo = Path(fx["repo"])
            subprocess.run(
                [
                    "git",
                    "tag",
                    "-a",
                    VERSION,
                    str(fx["commit"]),
                    "-m",
                    "MoonSight v1.0.0",
                ],
                cwd=repo,
                check=True,
            )

            original_fake = fake

            def limited_run(
                argv: list[str], **kwargs: Any
            ) -> subprocess.CompletedProcess[str]:
                result = original_fake(argv, **kwargs)
                # After upload, force assets to remain incomplete so verify fails.
                if argv[:3] == ["gh", "release", "upload"]:
                    original_fake.state["assets"] = [WEB]
                if argv[:3] == ["gh", "release", "view"]:
                    body = json.dumps(
                        {
                            "isDraft": True,
                            "tagName": VERSION,
                            "assets": [{"name": WEB}],
                        }
                    )
                    return subprocess.CompletedProcess(argv, 0, body, "")
                return result

            limited_run.calls = original_fake.calls  # type: ignore[attr-defined]

            with patch.object(publisher, "run_command", side_effect=limited_run):
                code = publisher.run(
                    cli_args(fx, "--execute", "--authorize", "v1.0.0")
                )
            self.assertNotEqual(code, 0)
            self.assertFalse(
                any(
                    a[:3] == ["gh", "release", "edit"] and "--draft=false" in a
                    for a in original_fake.calls
                )
            )

    def test_execute_refuses_digest_mismatch_on_download(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fx = make_fixture(root)
            fake = make_fake_run(fx, corrupt_download=WEB)
            with patch.object(publisher, "run_command", side_effect=fake):
                code = publisher.run(
                    cli_args(fx, "--execute", "--authorize", "v1.0.0")
                )
            self.assertNotEqual(code, 0)
            self.assertFalse(
                any(
                    a[:3] == ["gh", "release", "edit"] and "--draft=false" in a
                    for a in fake.calls
                )
            )

    def test_execute_resumes_existing_correct_tag_and_draft(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fx = make_fixture(root)
            repo = Path(fx["repo"])
            commit = str(fx["commit"])
            subprocess.run(
                ["git", "tag", "-a", VERSION, commit, "-m", "MoonSight v1.0.0"],
                cwd=repo,
                check=True,
            )
            fake = make_fake_run(
                fx,
                release_exists=True,
                remote_assets=list(ALL_ATTACHMENTS),
                remote_tag_sha=commit,
                local_tag_sha=commit,
            )
            with patch.object(publisher, "run_command", side_effect=fake):
                code = publisher.run(
                    cli_args(fx, "--execute", "--authorize", "v1.0.0")
                )
            self.assertEqual(code, 0, msg=f"calls={fake.calls}")
            # Should not re-create tag or release
            self.assertFalse(
                any(
                    a[0] == "git" and "tag" in a and "-a" in a
                    for a in fake.calls
                )
            )
            self.assertFalse(
                any(a[:3] == ["gh", "release", "create"] for a in fake.calls)
            )
            self.assertTrue(
                any(
                    a[:3] == ["gh", "release", "edit"] and "--draft=false" in a
                    for a in fake.calls
                )
            )


if __name__ == "__main__":
    unittest.main()
