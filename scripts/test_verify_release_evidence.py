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
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

from release_schema import REQUIRED_EVIDENCE_IDS  # noqa: E402
import verify_release_evidence  # noqa: E402


VERIFIER = SCRIPTS / "verify_release_evidence.py"
WEB_PATH = "MoonSight-v1.0.0-web-x86_64.zip"
APPIMAGE_PATH = "MoonSight-v1.0.0-linux-x86_64.AppImage"
DEB_PATH = "MoonSight-v1.0.0-linux-x86_64.deb"
RPM_PATH = "MoonSight-v1.0.0-linux-x86_64.rpm"
ARTIFACT_DIGESTS = {
    WEB_PATH: "a" * 64,
    APPIMAGE_PATH: "d" * 64,
    DEB_PATH: "e" * 64,
    RPM_PATH: "f" * 64,
}


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
        "attempt_id": "rc-20260713T030000Z-111111111111",
        "candidate": {
            "version": "v1.0.0",
            "commit": candidate_commit,
            "architecture": "x86_64",
            "clean_tree": True,
            "built_at_utc": "2026-07-13T03:00:00Z",
            "build_host": "release-builder.example",
            "artifacts": [
                {
                    "path": path,
                    "size_bytes": 123,
                    "sha256": digest,
                }
                for path, digest in ARTIFACT_DIGESTS.items()
            ],
        },
        "toolchains": {
            "moon": "0.6.29+3f4c5d6",
            "node": "24.4.0",
            "rustc": "1.88.0",
            "tauri_cli": "2.7.1",
        },
        "system": {
            "build_os": "Ubuntu 24.04.2 LTS",
            "kernel": "6.8.0-63-generic",
            "fedora": "Fedora Linux 42",
            "arch": "Arch Linux 2026.07.01",
        },
        "reproducibility": {
            "input_sha256": "6" * 64,
            "report": {
                "path": "reports/reproducibility.json",
                "sha256": "7" * 64,
            },
        },
        "validation_targets": {
            "chromium": "138.0.7204.92",
            "firefox": "140.0.4",
            "webkitgtk": "2.48.3",
        },
        "required_evidence_ids": list(REQUIRED_EVIDENCE_IDS),
        "automated_checks": [
            {
                "id": "benchmark",
                "status": "PASS",
                "input_sha256": "8" * 64,
                "report": {
                    "path": "reports/benchmark.json",
                    "sha256": "9" * 64,
                },
            },
            {
                "id": "reproducibility",
                "status": "PASS",
                "input_sha256": "6" * 64,
                "report": {
                    "path": "reports/reproducibility.json",
                    "sha256": "7" * 64,
                },
            },
        ],
        "notice": "Candidate identity does not authorize publication.",
    }


def artifact_for_evidence(evidence_id: str) -> str:
    if evidence_id.startswith("W1-") or evidence_id == "C1-web":
        return WEB_PATH
    if evidence_id.endswith("-deb"):
        return DEB_PATH
    if evidence_id.endswith("-rpm"):
        return RPM_PATH
    return APPIMAGE_PATH


def negative_fixtures() -> list[dict[str, Any]]:
    return [
        {
            "source_artifact": {
                "path": WEB_PATH,
                "sha256": ARTIFACT_DIGESTS[WEB_PATH],
            },
            "transformation": transformation,
            "derived_artifact_sha256": str(index) * 64,
        }
        for index, transformation in enumerate(
            ("missing-msb", "empty-msb", "corrupt-msb"), start=1
        )
    ]


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
                    "path": artifact_for_evidence(evidence_id),
                    "sha256": ARTIFACT_DIGESTS[
                        artifact_for_evidence(evidence_id)
                    ],
                },
                "record_path": f"{index:02d}-{evidence_id}.json",
                "record_sha256": f"{index + 1:x}" * 64,
                "public_evidence_sha256": "b" * 64,
                "raw_evidence_sha256": "c" * 64,
                **(
                    {"negative_fixtures": negative_fixtures()}
                    if evidence_id.startswith("W1-")
                    else {}
                ),
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

    def test_rejects_each_omitted_candidate_schema_category(self) -> None:
        mutations: tuple[
            tuple[str, Callable[[dict[str, Any]], None], str], ...
        ] = (
            (
                "attempt",
                lambda candidate: candidate.pop("attempt_id"),
                "candidate.attempt_id must be a non-empty string",
            ),
            (
                "build",
                lambda candidate: candidate["candidate"].pop("architecture"),
                "candidate.architecture must equal x86_64",
            ),
            (
                "toolchain",
                lambda candidate: candidate["toolchains"].pop("moon"),
                "candidate.toolchains.moon must be a non-empty string",
            ),
            (
                "system",
                lambda candidate: candidate["system"].pop("fedora"),
                "candidate.system.fedora must be a non-empty string",
            ),
            (
                "validation",
                lambda candidate: candidate["validation_targets"].pop("firefox"),
                "candidate.validation_targets.firefox must be a non-empty string",
            ),
            (
                "reproducibility",
                lambda candidate: candidate["reproducibility"].pop("report"),
                "candidate.reproducibility.report must be an object",
            ),
        )
        for category, mutate, expected_reason in mutations:
            with self.subTest(category=category), tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                repo, candidate, index, output = self.prepare(
                    root, mutate_candidate=mutate
                )

                result = run_verifier(repo, candidate, index, output)

                self.assert_rejected(result, output, expected_reason)

    def test_rejects_missing_w1_negative_fixture_provenance(self) -> None:
        def remove_fixtures(index: dict[str, Any]) -> None:
            index["records"][0].pop("negative_fixtures")

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repo, candidate, index, output = self.prepare(
                root, mutate_index=remove_fixtures
            )

            result = run_verifier(repo, candidate, index, output)

            self.assert_rejected(
                result,
                output,
                "records[0].negative_fixtures must contain missing-msb",
            )

    def test_rejects_w1_negative_fixture_from_another_artifact(self) -> None:
        def change_source_digest(index: dict[str, Any]) -> None:
            index["records"][0]["negative_fixtures"][0]["source_artifact"][
                "sha256"
            ] = "0" * 64

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repo, candidate, index, output = self.prepare(
                root, mutate_index=change_source_digest
            )

            result = run_verifier(repo, candidate, index, output)

            self.assert_rejected(
                result,
                output,
                (
                    "records[0].negative_fixtures[0].source_artifact.sha256 "
                    "must equal candidate Web artifact"
                ),
            )

    def test_rejects_private_or_parent_evidence_index_references(self) -> None:
        mutations: tuple[
            tuple[str, Callable[[dict[str, Any]], None], str], ...
        ] = (
            (
                "record",
                lambda index: index["records"][0].__setitem__(
                    "record_path", "../private-record.json"
                ),
                "records[0].record_path must be a public relative path",
            ),
            (
                "fixture",
                lambda index: index["records"][0]["negative_fixtures"][0][
                    "source_artifact"
                ].__setitem__("path", "../private-web.zip"),
                (
                    "records[0].negative_fixtures[0].source_artifact.path "
                    "must be a public relative path"
                ),
            ),
        )
        for reference, mutate, expected_reason in mutations:
            with self.subTest(reference=reference), tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                repo, candidate, index, output = self.prepare(
                    root, mutate_index=mutate
                )

                result = run_verifier(repo, candidate, index, output)

                self.assert_rejected(result, output, expected_reason)

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
            (release_dir / WEB_PATH).write_bytes(b"untracked release content")

            result = run_verifier(repo, candidate, index, output)

            self.assert_rejected(result, output, "worktree must be clean")

    def test_existing_v1_tag_writes_failure_report(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repo, candidate, index, output = self.prepare(root)
            subprocess.run(["git", "tag", "v1.0.0"], cwd=repo, check=True)

            result = run_verifier(repo, candidate, index, output)

            self.assert_rejected(result, output, "refs/tags/v1.0.0 must not exist")

    def test_show_ref_rc_1_is_absent_and_other_nonzero_is_gate_error(self) -> None:
        candidate_commit = "1" * 40
        head = subprocess.CompletedProcess(
            ["git", "rev-parse", "HEAD"],
            0,
            stdout=f"{candidate_commit}\n",
            stderr="",
        )
        status = subprocess.CompletedProcess(
            ["git", "status", "--porcelain=v1"], 0, stdout="", stderr=""
        )
        for returncode, expected_error in (
            (1, None),
            (2, "cannot inspect refs/tags/v1.0.0"),
        ):
            with self.subTest(returncode=returncode):
                tag = subprocess.CompletedProcess(
                    ["git", "show-ref"],
                    returncode,
                    stdout="",
                    stderr="tag lookup failed",
                )
                errors: list[str] = []
                with patch.object(
                    verify_release_evidence,
                    "git",
                    side_effect=(head, status, tag),
                ):
                    verify_release_evidence.validate_git_state(
                        Path("."), candidate_commit, errors
                    )

                if expected_error is None:
                    self.assertEqual(errors, [])
                else:
                    self.assertTrue(
                        any(expected_error in error for error in errors), errors
                    )

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
