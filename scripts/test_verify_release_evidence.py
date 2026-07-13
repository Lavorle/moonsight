from __future__ import annotations

import copy
import hashlib
import json
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

from release_schema import REQUIRED_EVIDENCE_IDS  # noqa: E402


VERIFIER = SCRIPTS / "verify_release_evidence.py"
ARTIFACT_PATH = "MoonSight-v1.0.0-web-x86_64.zip"
ARTIFACT_DIGEST = "a" * 64


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=repo,
        text=True,
        capture_output=True,
        check=False,
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
    (repo / "tracked-release-content.txt").write_text("frozen\n", encoding="utf-8")
    subprocess.run(["git", "add", "."], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-qm", "candidate"], cwd=repo, check=True)
    candidate_commit = git(repo, "rev-parse", "HEAD").stdout.strip()
    return repo, candidate_commit


def candidate_manifest(candidate_commit: str) -> dict[str, Any]:
    return {
        "schema_version": 2,
        "candidate": {
            "version": "v1.0.0",
            "commit": candidate_commit,
            "artifacts": [
                {
                    "path": ARTIFACT_PATH,
                    "size_bytes": 123,
                    "sha256": ARTIFACT_DIGEST,
                }
            ],
        },
        "required_evidence_ids": list(REQUIRED_EVIDENCE_IDS),
        "automated_checks": [
            {"id": "benchmark", "status": "PASS"},
            {"id": "reproducibility", "status": "PASS"},
        ],
    }


def evidence_index(
    candidate_path: Path, candidate: dict[str, Any]
) -> dict[str, Any]:
    candidate_commit = candidate["candidate"]["commit"]
    return {
        "schema_version": 1,
        "candidate_commit": candidate_commit,
        "candidate_manifest": {
            "path": candidate_path.name,
            "sha256": sha256_file(candidate_path),
        },
        "aggregate_status": "PASS",
        "records": [
            {
                "id": evidence_id,
                "status": "PASS",
                "candidate_commit": candidate_commit,
                "artifact": {
                    "path": ARTIFACT_PATH,
                    "sha256": ARTIFACT_DIGEST,
                },
                "record_path": f"{index:02d}-{evidence_id}.json",
                "record_sha256": f"{index + 1:x}" * 64,
                "public_evidence_sha256": "b" * 64,
                "raw_evidence_sha256": "c" * 64,
            }
            for index, evidence_id in enumerate(REQUIRED_EVIDENCE_IDS)
        ],
    }


def run_verifier(
    repo: Path,
    candidate: Path,
    index: Path,
    output: Path,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "python3",
            str(VERIFIER),
            "--repo",
            str(repo),
            "--candidate",
            str(candidate),
            "--index",
            str(index),
            "--output",
            str(output),
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


class VerifyReleaseEvidenceTests(unittest.TestCase):
    def prepare(
        self,
        root: Path,
        *,
        mutate_candidate: Callable[[dict[str, Any]], None] | None = None,
        mutate_index: Callable[[dict[str, Any]], None] | None = None,
    ) -> tuple[Path, Path, Path, Path]:
        repo, candidate_commit = init_repo(root)
        candidate = candidate_manifest(candidate_commit)
        if mutate_candidate is not None:
            mutate_candidate(candidate)
        candidate_path = root / "candidate.json"
        write_json(candidate_path, candidate)
        index = evidence_index(candidate_path, candidate)
        if mutate_index is not None:
            mutate_index(index)
        index_path = root / "evidence-index.json"
        write_json(index_path, index)
        return repo, candidate_path, index_path, root / "final-gate.json"

    def assert_rejected(
        self,
        result: subprocess.CompletedProcess[str],
        output: Path,
        expected_reason: str,
    ) -> None:
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertTrue(output.exists(), result.stderr)
        report = json.loads(output.read_text(encoding="utf-8"))
        self.assertFalse(report["technical_release_ready"])
        self.assertFalse(report["publication_authorized"])
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o444)
        self.assertTrue(
            any(expected_reason in reason for reason in report["reasons"]),
            report["reasons"],
        )

    def test_all_13_pass_produces_immutable_technical_gate_without_authorization(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repo, candidate, index, output = self.prepare(root)

            result = run_verifier(repo, candidate, index, output)

            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["schema_version"], 1)
            self.assertEqual(report["candidate_sha256"], sha256_file(candidate))
            self.assertEqual(report["evidence_index_sha256"], sha256_file(index))
            self.assertTrue(report["technical_release_ready"])
            self.assertFalse(report["publication_authorized"])
            self.assertEqual(report["reasons"], [])
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o444)

    def test_missing_id_writes_failure_report(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            missing_id = REQUIRED_EVIDENCE_IDS[-1]
            prepared = self.prepare(
                root, mutate_index=lambda index: index["records"].pop()
            )
            repo, candidate, index, output = prepared

            result = run_verifier(repo, candidate, index, output)

            self.assert_rejected(result, output, f"missing required evidence IDs: {missing_id}")

    def test_duplicate_id_writes_failure_report(self) -> None:
        def duplicate(index: dict[str, Any]) -> None:
            index["records"].append(copy.deepcopy(index["records"][0]))

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repo, candidate, index, output = self.prepare(
                root, mutate_index=duplicate
            )

            result = run_verifier(repo, candidate, index, output)

            self.assert_rejected(result, output, "duplicate evidence ID")

    def test_wrong_record_commit_writes_failure_report(self) -> None:
        def wrong_commit(index: dict[str, Any]) -> None:
            index["records"][0]["candidate_commit"] = "2" * 40

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repo, candidate, index, output = self.prepare(
                root, mutate_index=wrong_commit
            )

            result = run_verifier(repo, candidate, index, output)

            self.assert_rejected(
                result, output, "records[0].candidate_commit must equal candidate commit"
            )

    def test_artifact_mismatch_writes_failure_report(self) -> None:
        def wrong_artifact(index: dict[str, Any]) -> None:
            index["records"][0]["artifact"]["sha256"] = "d" * 64

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repo, candidate, index, output = self.prepare(
                root, mutate_index=wrong_artifact
            )

            result = run_verifier(repo, candidate, index, output)

            self.assert_rejected(
                result, output, "records[0].artifact.sha256 must equal candidate artifact"
            )

    def test_failed_automation_writes_failure_report(self) -> None:
        def fail_automation(candidate: dict[str, Any]) -> None:
            candidate["automated_checks"][0]["status"] = "FAIL"

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repo, candidate, index, output = self.prepare(
                root, mutate_candidate=fail_automation
            )

            result = run_verifier(repo, candidate, index, output)

            self.assert_rejected(
                result, output, "automated_checks[0].status must be PASS"
            )

    def test_not_run_evidence_writes_failure_report(self) -> None:
        def not_run(index: dict[str, Any]) -> None:
            index["records"][0]["status"] = "NOT_RUN"

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repo, candidate, index, output = self.prepare(
                root, mutate_index=not_run
            )

            result = run_verifier(repo, candidate, index, output)

            self.assert_rejected(result, output, "records[0].status must be PASS")

    def test_head_different_from_candidate_writes_failure_report(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repo, candidate, index, output = self.prepare(root)
            (repo / "later.txt").write_text("later\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-qm", "later"], cwd=repo, check=True)

            result = run_verifier(repo, candidate, index, output)

            self.assert_rejected(result, output, "HEAD must equal candidate commit")

    def test_dirty_tracked_release_content_writes_failure_report(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repo, candidate, index, output = self.prepare(root)
            (repo / "tracked-release-content.txt").write_text(
                "changed\n", encoding="utf-8"
            )

            result = run_verifier(repo, candidate, index, output)

            self.assert_rejected(result, output, "worktree must be clean")

    def test_untracked_release_content_writes_failure_report(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repo, candidate, index, output = self.prepare(root)
            release_dir = repo / "dist"
            release_dir.mkdir()
            (release_dir / ARTIFACT_PATH).write_bytes(b"untracked release content")

            result = run_verifier(repo, candidate, index, output)

            self.assert_rejected(result, output, "worktree must be clean")

    def test_existing_v1_tag_writes_failure_report(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repo, candidate, index, output = self.prepare(root)
            subprocess.run(["git", "tag", "v1.0.0"], cwd=repo, check=True)

            result = run_verifier(repo, candidate, index, output)

            self.assert_rejected(result, output, "refs/tags/v1.0.0 must not exist")

    def test_existing_output_is_never_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repo, candidate, index, output = self.prepare(root)
            output.write_text("keep\n", encoding="utf-8")

            result = run_verifier(repo, candidate, index, output)

            self.assertEqual(result.returncode, 1)
            self.assertEqual(output.read_text(encoding="utf-8"), "keep\n")
            self.assertIn("immutable final gate report already exists", result.stderr)


if __name__ == "__main__":
    unittest.main()
