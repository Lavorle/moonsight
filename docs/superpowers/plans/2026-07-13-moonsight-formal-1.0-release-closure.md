# MoonSight Formal 1.0 Release Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish Formal 1.0 release tooling (Tasks 6–8), freeze an immutable candidate, collect the 13-item real evidence matrix, pass Final Gate, and publish annotated `v1.0.0` only after operator secondary confirmation.

**Architecture:** Continue on `feat/formal-1.0-release` where Tasks 1–5 already own schema, candidate identity, evidence index, technical gate, and artifact builds. Add a draft-first GitHub publisher, align CI/docs, prove a local tooling dry-run, then execute the operational runbook outside the frozen candidate tree for W1/D1/C1 and publication.

**Tech Stack:** Python 3 stdlib + `unittest`, Bash, Git, GitHub CLI (`gh`), MoonBit, Node/Vite/Svelte, Rust/Tauri 2.

**Spec:** [`docs/superpowers/specs/2026-07-13-moonsight-formal-1.0-release-closure-design.md`](../specs/2026-07-13-moonsight-formal-1.0-release-closure-design.md)  
**Product contract (authoritative for matrix):** [`docs/superpowers/specs/2026-07-13-moonsight-formal-1.0-public-release-design.md`](../specs/2026-07-13-moonsight-formal-1.0-public-release-design.md)  
**Prior plan (Tasks 1–5 done):** [`docs/superpowers/plans/2026-07-13-moonsight-formal-1.0-public-release.md`](./2026-07-13-moonsight-formal-1.0-public-release.md)

---

## Global Constraints

- Worktree for implementation: `/mnt/nvme1n1p2/moonsight/.worktrees/formal-1.0-release` on branch `feat/formal-1.0-release` (Tasks 1–5 already landed). Cherry-pick or merge the release-closure design commit from `main` if missing.
- Target version is exactly `v1.0.0`. Annotated tag must equal the frozen candidate SHA.
- Public artifacts (authoritative names from `scripts/build_release_artifacts.sh`):
  - `moonsight-web-x86_64-v1.0.0.zip`
  - `moonsight-linux-x86_64-v1.0.0.AppImage`
  - `moonsight-linux-x86_64-v1.0.0.deb`
  - `moonsight-linux-x86_64-v1.0.0.rpm`
  - `SHA256SUMS`
- Exactly 13 evidence IDs from `scripts/release_schema.py` `REQUIRED_EVIDENCE_IDS`.
- Publisher defaults to dry-run. Real publication requires `--execute --authorize v1.0.0` **and** human secondary confirmation in the session.
- No runtime feature work. No Windows/macOS. No GitHub Pages. Do not shrink the support matrix.
- Final Gate `technical_release_ready` ≠ publication authorization.

## Baseline (do not re-implement)

Already present on `feat/formal-1.0-release` (verify before coding):

| Component | Path |
|-----------|------|
| Evidence IDs + digests | `scripts/release_schema.py` |
| Candidate identity + guard | `scripts/rc_manifest.py` |
| Record validate + index | `scripts/release_evidence.py` |
| Final technical gate | `scripts/verify_release_evidence.py` |
| Artifact dual-build | `scripts/build_release_artifacts.sh` |
| Repro comparison | `scripts/compare_reproducible_builds.py` |
| Template | `scripts/release-evidence-template.json` |
| CI unittest job | `.github/workflows/ci.yml` job `release-tooling` |

Baseline check:

```bash
cd /mnt/nvme1n1p2/moonsight/.worktrees/formal-1.0-release
python3 -m unittest scripts/test_release_schema.py scripts/test_release_evidence.py scripts/test_verify_release_evidence.py -v
```

Expected: all tests `OK` (53+).

---

## File Structure (this plan)

| File | Responsibility |
|------|----------------|
| Create `scripts/publish_github_release.py` | Plan + execute draft-first tag/Release; dry-run default |
| Create `scripts/test_publish_github_release.py` | Mocked subprocess tests for planner and execute paths |
| Modify `.github/workflows/ci.yml` | Ensure publisher tests are covered (already discovers `test_*.py`) |
| Modify `docs/release-1.0-verification.md` | 13 exact IDs, external evidence lifecycle, remain BLOCKED until real runs |
| Modify `docs/formal-1.0-rc-tooling.md` | Document publisher + gate CLI |
| Modify `README.md` / `README.en.md` / `README.mbt.md` | Support matrix honest statements |
| Modify `CHANGELOG.md` | Tooling readiness without claiming matrix PASS |
| Create `.superpowers/sdd/formal-1.0-release-tooling-final-verify-report.md` | Task 8 tooling PASS vs GUI NOT RUN |
| Ops only (outside git or outside candidate): release dir, evidence records, index, gate, raw evidence |

---

## Behavior Coverage

| Scenario | Covered by |
|----------|------------|
| S5 Draft-first publish | Task 6 |
| S4 Gate rejection (regression) | Task 8 synthetic fixtures |
| S1–S3 real matrix | Ops-2 |
| Technical readiness without auth | Ops-3 |
| Authorized publication | Ops-4 |
| Branch hygiene after release | Ops-5 |

---

### Task 6: Draft-First GitHub Publisher

**Files:**
- Create: `scripts/publish_github_release.py`
- Create: `scripts/test_publish_github_release.py`

**Working directory:** `.worktrees/formal-1.0-release`

**Interfaces:**
- CLI: `python3 scripts/publish_github_release.py --repo REPO --candidate CANDIDATE.json --index INDEX.json --gate GATE.json --artifacts DIR --notes NOTES.md [--execute] [--authorize v1.0.0]`
- Default mode: dry-run; print JSON plan of argv arrays; exit 0; no network/git mutations.
- Execute mode requires both `--execute` and `--authorize v1.0.0`.
- Never use `shell=True`. Inject runner via function parameter or module-level `run_command` for tests.

- [ ] **Step 1: Write failing tests**

Create `scripts/test_publish_github_release.py`:

```python
from __future__ import annotations

import hashlib
import json
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
                {"path": n, "size_bytes": (artifacts / n).stat().st_size, "sha256": digests[n]}
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


class PublishPlannerTests(unittest.TestCase):
    def test_dry_run_emits_commands_without_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fx = make_fixture(root)
            plan = publisher.plan_commands(
                repo=fx["repo"],
                candidate_path=fx["candidate"],
                index_path=fx["index"],
                gate_path=fx["gate"],
                artifacts_dir=fx["artifacts"],
                notes_path=fx["notes"],
            )
            argv_lists = [c["argv"] for c in plan["commands"]]
            self.assertTrue(any(a[:3] == ["git", "tag", "-a"] for a in argv_lists))
            self.assertTrue(
                any(a[:3] == ["gh", "release", "create"] for a in argv_lists)
            )
            # publication is last mutating command and uses draft=false
            last = argv_lists[-1]
            self.assertEqual(last[:3], ["gh", "release", "edit"])
            self.assertIn("--draft=false", last)
            # dry-run path does not create tag
            self.assertNotEqual(
                git(fx["repo"], "show-ref", "--verify", "refs/tags/v1.0.0").returncode,
                0,
            )

    def test_execute_requires_authorize_v1(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fx = make_fixture(root)
            code = publisher.run(
                [
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
                    "--execute",
                ]
            )
            self.assertNotEqual(code, 0)

    def test_execute_refuses_when_gate_not_ready(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fx = make_fixture(root)
            gate = json.loads(fx["gate"].read_text(encoding="utf-8"))
            gate["technical_release_ready"] = False
            gate["reasons"] = ["synthetic block"]
            write_json(fx["gate"], gate)
            code = publisher.run(
                [
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
                    "--execute",
                    "--authorize",
                    "v1.0.0",
                ]
            )
            self.assertNotEqual(code, 0)

    def test_execute_sequence_is_tag_then_draft_then_upload_then_verify_then_publish(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fx = make_fixture(root)
            calls: list[list[str]] = []

            def fake_run(argv: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
                calls.append(list(argv))
                # minimal successful responses for inspect / auth / download
                if argv[:2] == ["gh", "auth"]:
                    return subprocess.CompletedProcess(argv, 0, "ok", "")
                if argv[:3] == ["gh", "release", "view"]:
                    # first view: missing; later views return attachment names
                    if any(c[:3] == ["gh", "release", "create"] for c in calls[:-1]):
                        body = json.dumps(
                            {
                                "isDraft": True,
                                "assets": [{"name": n} for n in ARTIFACTS]
                                + [
                                    {"name": "SHA256SUMS"},
                                    {"name": "candidate.json"},
                                    {"name": "evidence-index.json"},
                                    {"name": "final-gate.json"},
                                    {"name": "notes.md"},
                                ],
                            }
                        )
                        return subprocess.CompletedProcess(argv, 0, body, "")
                    return subprocess.CompletedProcess(argv, 1, "", "not found")
                if argv[:3] == ["gh", "release", "download"]:
                    # download into cwd-like out dir if present
                    return subprocess.CompletedProcess(argv, 0, "", "")
                return subprocess.CompletedProcess(argv, 0, "", "")

            with patch.object(publisher, "run_command", side_effect=fake_run):
                # Also stub attachment byte verification by writing expected files
                # when download is requested — implementer may refine fake_run.
                code = publisher.run(
                    [
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
                        "--execute",
                        "--authorize",
                        "v1.0.0",
                    ]
                )
            self.assertEqual(code, 0)
            # order constraints
            tag_i = next(i for i, a in enumerate(calls) if a[:3] == ["git", "tag", "-a"])
            create_i = next(
                i for i, a in enumerate(calls) if a[:3] == ["gh", "release", "create"]
            )
            publish_i = next(
                i
                for i, a in enumerate(calls)
                if a[:3] == ["gh", "release", "edit"] and "--draft=false" in a
            )
            self.assertLess(tag_i, create_i)
            self.assertLess(create_i, publish_i)


if __name__ == "__main__":
    unittest.main()
```

Notes for the implementer: if `fake_run` needs to materialize downloaded attachment bytes for digest checks, write each local artifact into the download directory when handling `gh release download`. Expand tests for: wrong authorize string, existing tag peels to other SHA, incomplete remote attachments, gate `publication_authorized` ignored (must stay operator-driven).

- [ ] **Step 2: Confirm failure**

Run:

```bash
cd /mnt/nvme1n1p2/moonsight/.worktrees/formal-1.0-release
python3 -m unittest scripts/test_publish_github_release.py -v
```

Expected: `ModuleNotFoundError: No module named 'publish_github_release'` (or import error).

- [ ] **Step 3: Implement command planner and dry-run**

Create `scripts/publish_github_release.py` with at least:

```python
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable

from release_schema import read_object, sha256_file

VERSION = "v1.0.0"
REQUIRED_ATTACHMENTS_EXTRA = (
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


def load_inputs(
    candidate_path: Path,
    index_path: Path,
    gate_path: Path,
    artifacts_dir: Path,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], list[str]]:
    candidate = read_object(candidate_path, "candidate")
    index = read_object(index_path, "index")
    gate = read_object(gate_path, "gate")
    artifact_names = [
        item["path"] for item in candidate["candidate"]["artifacts"]
    ]
    for name in artifact_names + ["SHA256SUMS"]:
        path = artifacts_dir / name
        if not path.is_file():
            raise SystemExit(f"error: missing artifact file: {path}")
    return candidate, index, gate, artifact_names


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
    commit = candidate["candidate"]["commit"]
    if candidate["candidate"]["version"] != VERSION:
        raise SystemExit("error: candidate.version must be v1.0.0")
    if not gate.get("technical_release_ready"):
        raise SystemExit("error: technical_release_ready is false")

    upload = [artifacts_dir / n for n in artifact_names]
    upload.append(artifacts_dir / "SHA256SUMS")
    # staged copies of metadata under artifacts_dir or temp are fine;
    # plan must list concrete argv only.
    commands = [
        {
            "phase": "tag",
            "argv": [
                "git",
                "-C",
                str(repo),
                "tag",
                "-a",
                VERSION,
                commit,
                "-m",
                "MoonSight v1.0.0",
            ],
        },
        {
            "phase": "push-tag",
            "argv": ["git", "-C", str(repo), "push", "origin", f"refs/tags/{VERSION}"],
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
                "MoonSight v1.0.0",
                "--notes-file",
                str(notes_path),
                "--repo",
                # resolve from git remote or require --github-repo flag;
                # implementer: prefer `gh` default repo from cwd=repo
            ],
        },
        # upload phases: gh release upload VERSION files... --clobber false
        # verify phases: gh release view --json assets; gh release download
        {
            "phase": "publish",
            "argv": ["gh", "release", "edit", VERSION, "--draft=false"],
        },
    ]
    # Expand create-draft/upload/verify into full concrete argv lists in real code.
    # Keep publication as the final mutating command.
    return {
        "mode": "plan",
        "version": VERSION,
        "commit": commit,
        "commands": commands,
    }


def preflight_execute(
    repo: Path,
    candidate: dict[str, Any],
    gate: dict[str, Any],
) -> None:
    if not gate.get("technical_release_ready"):
        raise SystemExit("error: technical_release_ready is false")
    head = run_command(["git", "-C", str(repo), "rev-parse", "HEAD"])
    if head.returncode != 0 or head.stdout.strip() != candidate["candidate"]["commit"]:
        raise SystemExit("error: HEAD must equal candidate commit")
    status = run_command(["git", "-C", str(repo), "status", "--porcelain=v1"])
    if status.returncode != 0 or status.stdout.strip():
        raise SystemExit("error: worktree must be clean")
    auth = run_command(["gh", "auth", "status"])
    if auth.returncode != 0:
        raise SystemExit("error: gh auth status failed")


def run(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Draft-first GitHub release publisher")
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--index", type=Path, required=True)
    parser.add_argument("--gate", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--notes", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--authorize", default="")
    args = parser.parse_args(argv)

    plan = plan_commands(
        repo=args.repo,
        candidate_path=args.candidate,
        index_path=args.index,
        gate_path=args.gate,
        artifacts_dir=args.artifacts,
        notes_path=args.notes,
    )
    if not args.execute:
        print(json.dumps({"mode": "dry-run", "commands": plan["commands"]}, indent=2))
        return 0
    if args.authorize != VERSION:
        print("error: explicit --authorize v1.0.0 required", file=sys.stderr)
        return 2

    candidate = read_object(args.candidate, "candidate")
    gate = read_object(args.gate, "gate")
    preflight_execute(args.repo, candidate, gate)

    # Resumable execute (required behavior):
    # 1. Inspect local tag / remote tag / existing release.
    # 2. Create annotated tag only if absent; if present, peel and require exact candidate SHA.
    # 3. Push tag if remote lacks it; conflict SHA => stop for human.
    # 4. Create draft release if absent; else resume draft.
    # 5. Upload only missing attachments: four artifacts + SHA256SUMS + copies of
    #    candidate.json, evidence-index.json (from --index), final-gate.json (from --gate), notes.md.
    # 6. gh release view --json assets; download all into temp dir; sha256 byte-compare to local.
    # 7. Re-peel remote tag == candidate; re-check draft assets; then
    #    gh release edit v1.0.0 --draft=false.
    # Use run_command for every subprocess. Fail closed; leave draft on mismatch.

    for command in plan["commands"]:
        result = run_command(command["argv"], cwd=args.repo)
        if result.returncode != 0:
            print(result.stderr, file=sys.stderr)
            return result.returncode
    return 0


def main() -> int:
    return run()


if __name__ == "__main__":
    raise SystemExit(main())
```

Implement the resumable path fully (the sketch above is the skeleton; tests define required order and refusal rules). Prefer operating `gh` with `cwd=repo` so the GitHub repo is inferred; drop hard-coded `--repo` owner/name unless tests require it.

- [ ] **Step 4: Run tests**

```bash
cd /mnt/nvme1n1p2/moonsight/.worktrees/formal-1.0-release
python3 -m unittest scripts/test_publish_github_release.py -v
python3 -m unittest discover -s scripts -p 'test_*.py'
```

Expected: all `OK`.

- [ ] **Step 5: Commit**

```bash
git add scripts/publish_github_release.py scripts/test_publish_github_release.py
git commit -m "feat: add draft-first GitHub release publisher"
```

---

### Task 7: CI and Release Documentation Alignment

**Files:**
- Modify: `.github/workflows/ci.yml` (only if publisher tests are not already covered by `python3 -m unittest discover -s scripts -p 'test_*.py'`)
- Modify: `docs/release-1.0-verification.md`
- Modify: `docs/formal-1.0-rc-tooling.md`
- Modify: `README.md`, `README.en.md`, `README.mbt.md` (whichever are present and user-facing)
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Confirm CI discovers publisher tests**

Open `.github/workflows/ci.yml` job `release-tooling`. It must contain:

```yaml
- name: Test benchmark, reproducibility, RC, and evidence validators
  run: python3 -m unittest discover -s scripts -p 'test_*.py'
```

If missing, add an equivalent step. Do **not** add steps that claim W1/D1/C1 PASS.

- [ ] **Step 2: Align verification doc**

In `docs/release-1.0-verification.md`:

1. Keep overall status **BLOCKED** until real candidate selected.
2. List every required ID exactly:

```text
W1-ubuntu-chromium
W1-ubuntu-firefox
W1-fedora-chromium
W1-fedora-firefox
W1-arch-chromium
W1-arch-firefox
D1-ubuntu-appimage
D1-ubuntu-deb
D1-fedora-appimage
D1-fedora-rpm
D1-arch-appimage
C1-web
C1-desktop
```

3. Document external evidence lifecycle: candidate freeze → collect records outside commit → `release_evidence.py build-index` → `verify_release_evidence.py` → operator secondary confirm → publisher.
4. Document artifact names matching `build_release_artifacts.sh`.
5. Leave candidate fields as `NOT SELECTED` / `NOT RUN` until Ops-1.

- [ ] **Step 3: Document publisher in RC tooling**

In `docs/formal-1.0-rc-tooling.md` add a section:

```markdown
## GitHub publisher

Dry-run (safe, no side effects):

```bash
python3 scripts/publish_github_release.py \
  --repo . \
  --candidate path/to/candidate.json \
  --index path/to/evidence-index.json \
  --gate path/to/final-gate.json \
  --artifacts path/to/first \
  --notes path/to/release-notes.md
```

Execute only after Final Gate PASS and human secondary confirmation:

```bash
python3 scripts/publish_github_release.py \
  --repo . \
  --candidate path/to/candidate.json \
  --index path/to/evidence-index.json \
  --gate path/to/final-gate.json \
  --artifacts path/to/first \
  --notes path/to/release-notes.md \
  --execute --authorize v1.0.0
```
```

- [ ] **Step 4: Support statements**

Update README files to state:

- Formal support: Linux x86_64
- Web: Chromium stable + Firefox stable on Ubuntu 24.04, Fedora current stable, Arch current
- Desktop: AppImage + deb + rpm as in public-release design
- Artifacts delivered via GitHub Release ZIP/packages, not GitHub Pages
- Release remains blocked until W1/D1/C1 pass against one immutable candidate SHA

- [ ] **Step 5: CHANGELOG honesty**

Ensure `[1.0.0] - Unreleased` (or equivalent) describes Formal 1.0 content + release tooling readiness, and **does not** claim matrix PASS or published tag.

- [ ] **Step 6: Run checks**

```bash
cd /mnt/nvme1n1p2/moonsight/.worktrees/formal-1.0-release
python3 -m unittest discover -s scripts -p 'test_*.py'
# optional if docs-site present and cheap:
# cd apps/docs-site && npm ci && npm run types:check && npm run build
```

Expected: Python tests `OK`; docs still say BLOCKED / NOT RUN for real matrix.

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/ci.yml docs/release-1.0-verification.md docs/formal-1.0-rc-tooling.md README.md README.en.md README.mbt.md CHANGELOG.md
git commit -m "docs: align Formal 1.0 release support and publisher runbook"
```

---

### Task 8: Full Local Tooling Verification and Candidate Dry Run

**Files:**
- Create: `.superpowers/sdd/formal-1.0-release-tooling-final-verify-report.md`
- Modify other files only if verification finds defects in Tasks 1–7 ownership.

- [ ] **Step 1: Run automated matrix (tooling + engine)**

```bash
cd /mnt/nvme1n1p2/moonsight/.worktrees/formal-1.0-release
export CC=gcc
moon fmt --check
moon check --target all
moon test
moon build --target wasm-gc --release host_web
cd apps/host-web && npm ci && npm test && npx tsc --noEmit && npm run build && cd ../..
moon run cmd/moonsightc --target native -- check demo/game
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
./scripts/verify-package.sh dist/demo
python3 -m unittest discover -s scripts -p 'test_*.py'
cd host_desktop/tauri && npm ci && cargo fmt --check --manifest-path src-tauri/Cargo.toml && cargo check --manifest-path src-tauri/Cargo.toml && cargo test --manifest-path src-tauri/Cargo.toml && cd ../..
```

Expected: every command exit 0. If a non-release product defect appears, fix on this branch with a separate commit, then re-run.

- [ ] **Step 2: Artifact dual-build smoke (may be long)**

```bash
RELEASE_OUT="$(mktemp -d /tmp/moonsight-rc-XXXX)"
./scripts/build_release_artifacts.sh --version v1.0.0 --out "$RELEASE_OUT"
python3 scripts/compare_reproducible_builds.py \
  "$RELEASE_OUT/first" "$RELEASE_OUT/second" \
  --allowlist scripts/reproducibility-normalization-v1.json \
  --output "$RELEASE_OUT/repro-report.json"
```

Expected: builder exits 0; repro report outcome PASS (or document BLOCKED with exact mismatch if environment cannot produce desktop bundles — do not fake PASS).

- [ ] **Step 3: Synthetic gate fixture (temporary directory only)**

Using Task 6 fixture style (or publisher tests' helpers), in a **temp dir**:

1. Create candidate JSON pointing at current `git rev-parse HEAD` **only if** that HEAD matches the synthetic commit you create in a temp git repo — prefer the temp-repo approach from tests so main worktree is untouched.
2. Build 13 PASS records + index via `python3 scripts/release_evidence.py build-index --candidate ... --records ... --output ...`
3. Run `python3 scripts/verify_release_evidence.py --repo TEMP_REPO --candidate ... --index ... --output ...`
4. Expect gate `technical_release_ready=true`, `publication_authorized=false`
5. Flip one record to `NOT_RUN`, rebuild index, re-run gate → must fail

- [ ] **Step 4: Publisher dry-run against synthetic fixture**

```bash
python3 scripts/publish_github_release.py \
  --repo "$TEMP_REPO" \
  --candidate "$CAND" \
  --index "$INDEX" \
  --gate "$GATE" \
  --artifacts "$ART_DIR" \
  --notes "$NOTES"
```

Expected: JSON plan printed; no tag created; last planned mutating command is `gh release edit v1.0.0 --draft=false`.

- [ ] **Step 5: Write verification report**

Create `.superpowers/sdd/formal-1.0-release-tooling-final-verify-report.md` with:

- Branch + HEAD SHA
- Automated matrix: PASS/FAIL per command group
- Artifact/repro: PASS/FAIL + paths
- Synthetic gate: PASS
- Publisher dry-run: PASS
- Explicit: **W1/D1/C1 real evidence: NOT RUN**
- Explicit: **v1.0.0 not published**

- [ ] **Step 6: Commit report**

```bash
git add .superpowers/sdd/formal-1.0-release-tooling-final-verify-report.md
git commit -m "test: verify Formal 1.0 release tooling dry-run"
```

---

## Operational Runbook (not optional for v1.0.0 endpoint)

Execute only after Tasks 6–8 are complete on a **clean** tree. Real evidence lives **outside** the candidate commit.

### Ops-1: Freeze candidate and build artifacts

- [ ] **Step 1: Ensure clean tree on release branch**

```bash
cd /mnt/nvme1n1p2/moonsight/.worktrees/formal-1.0-release
git status --porcelain
git rev-parse HEAD
```

Expected: empty porcelain. Record `CANDIDATE_SHA`.

- [ ] **Step 2: Build first+second artifact sets**

```bash
RELEASE_ROOT="$HOME/moonsight-release/v1.0.0-rc1"   # operator-chosen durable path
mkdir -p "$RELEASE_ROOT"
./scripts/build_release_artifacts.sh --version v1.0.0 --out "$RELEASE_ROOT/builds"
```

- [ ] **Step 3: Reproducibility + candidate identity**

```bash
python3 scripts/compare_reproducible_builds.py \
  "$RELEASE_ROOT/builds/first" "$RELEASE_ROOT/builds/second" \
  --allowlist scripts/reproducibility-normalization-v1.json \
  --output "$RELEASE_ROOT/repro-report.json"
# Follow docs/formal-1.0-rc-tooling.md to generate benchmark report if required by rc_manifest.generate
python3 scripts/rc_manifest.py generate \
  --candidate "$CANDIDATE_SHA" \
  --benchmark "$RELEASE_ROOT/benchmark-report.json" \
  --reproducibility "$RELEASE_ROOT/repro-report.json" \
  --metadata "$RELEASE_ROOT/builds/first/build-metadata.json" \
  --output "$RELEASE_ROOT/candidate.json"
python3 scripts/rc_manifest.py guard --candidate "$CANDIDATE_SHA" --repo .
```

Expected: `candidate.json` written once (`O_EXCL`); guard passes while HEAD stays at `$CANDIDATE_SHA`.

### Ops-2: Collect 13 real evidence records

For each ID in `REQUIRED_EVIDENCE_IDS`:

- [ ] Copy `scripts/release-evidence-template.json` → `$RELEASE_ROOT/records/<ID>.json`
- [ ] Fill environment, steps, attachments, digests for the matching artifact from `$RELEASE_ROOT/builds/first`
- [ ] Set `candidate_commit` to `$CANDIDATE_SHA`
- [ ] Run real play/install/save/reload/locale/rollback checks per `docs/release-1.0-verification.md`
- [ ] Redact public attachments; store raw evidence under `$RELEASE_ROOT/raw/<ID>/`
- [ ] Validate:

```bash
python3 scripts/release_evidence.py validate-record \
  "$RELEASE_ROOT/candidate.json" \
  "$RELEASE_ROOT/records/<ID>.json"
```

Expected: exit 0 only for well-formed PASS (or non-zero with clear errors). Any real FAIL stops publication path (new candidate required after fix).

### Ops-3: Evidence Index + Final Gate

```bash
python3 scripts/release_evidence.py build-index \
  --candidate "$RELEASE_ROOT/candidate.json" \
  --records "$RELEASE_ROOT/records" \
  --output "$RELEASE_ROOT/evidence-index.json"
python3 scripts/verify_release_evidence.py \
  --repo . \
  --candidate "$RELEASE_ROOT/candidate.json" \
  --index "$RELEASE_ROOT/evidence-index.json" \
  --output "$RELEASE_ROOT/final-gate.json"
python3 -c "import json; g=json.load(open('$RELEASE_ROOT/final-gate.json')); assert g['technical_release_ready'] is True; assert g.get('publication_authorized') is False"
```

Expected: gate file created; technical ready true; publication_authorized false.

### Ops-4: Secondary confirmation and publish

- [ ] **Step 1: Present operator summary** (human message must include):

  - candidate SHA
  - artifact SHA-256 list from `SHA256SUMS`
  - all 13 IDs PASS
  - final-gate path
  - remote target (`origin` / GitHub repo)

- [ ] **Step 2: Wait for explicit user approval** in chat or signed note: e.g. `AUTHORIZE PUBLISH v1.0.0 <fullsha>`

- [ ] **Step 3: Dry-run first**

```bash
python3 scripts/publish_github_release.py \
  --repo . \
  --candidate "$RELEASE_ROOT/candidate.json" \
  --index "$RELEASE_ROOT/evidence-index.json" \
  --gate "$RELEASE_ROOT/final-gate.json" \
  --artifacts "$RELEASE_ROOT/builds/first" \
  --notes "$RELEASE_ROOT/release-notes.md"
```

- [ ] **Step 4: Execute only after approval**

```bash
python3 scripts/publish_github_release.py \
  --repo . \
  --candidate "$RELEASE_ROOT/candidate.json" \
  --index "$RELEASE_ROOT/evidence-index.json" \
  --gate "$RELEASE_ROOT/final-gate.json" \
  --artifacts "$RELEASE_ROOT/builds/first" \
  --notes "$RELEASE_ROOT/release-notes.md" \
  --execute --authorize v1.0.0
```

- [ ] **Step 5: Verify remote**

```bash
git ls-remote --tags origin 'refs/tags/v1.0.0'
gh release view v1.0.0 --json isDraft,tagName,assets
```

Expected: remote tag peels to `$CANDIDATE_SHA`; release not draft; all attachments present with matching digests.

### Ops-5: Post-release hygiene

- [ ] Merge `feat/formal-1.0-release` into `main` via normal PR/merge (no rewrite of `v1.0.0` tree).
- [ ] Update CHANGELOG date / Unreleased → released **only on a commit after tag** if docs need it; never amend the tagged commit.
- [ ] Record final operator note under `$RELEASE_ROOT/PUBLISHED.md` with tag SHA and Release URL.
- [ ] Do **not** mark verification templates as PASS inside the tagged source tree if that would require mutating the candidate; public Evidence Index on the Release is the durable proof.

---

## Self-Review (plan author)

| Spec requirement | Task |
|------------------|------|
| Task 6 publisher dry-run/execute | Task 6 |
| Task 7 CI/docs | Task 7 |
| Task 8 tooling dry-run | Task 8 |
| Freeze candidate + artifacts | Ops-1 |
| 13 real evidence | Ops-2 |
| Index + Final Gate | Ops-3 |
| Secondary confirm + publish | Ops-4 |
| Merge/hygiene without rewriting tag | Ops-5 |
| No runtime features / no matrix shrink | Global constraints |
| Draft-first + digest verify | Task 6 + Ops-4 |

Placeholder scan: no TBD/TODO left as work instructions. Artifact names match `build_release_artifacts.sh`. Evidence IDs match `REQUIRED_EVIDENCE_IDS`.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-13-moonsight-formal-1.0-release-closure.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — execute tasks in this session with checkpoints  

**Which approach?**
