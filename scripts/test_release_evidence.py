from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

from release_evidence import validate_record  # noqa: E402
from release_schema import REQUIRED_EVIDENCE_IDS  # noqa: E402


TOOL = SCRIPTS / "release_evidence.py"
CANDIDATE_COMMIT = "1" * 40
PUBLIC_DIGEST = "b" * 64
RAW_DIGEST = "c" * 64
WEB_PATH = "moonsight-web-x86_64-v1.0.0.zip"
APPIMAGE_PATH = "moonsight-linux-x86_64-v1.0.0.AppImage"
DEB_PATH = "moonsight-linux-x86_64-v1.0.0.deb"
RPM_PATH = "moonsight-linux-x86_64-v1.0.0.rpm"
ARTIFACT_DIGESTS = {
    WEB_PATH: "a" * 64,
    APPIMAGE_PATH: "d" * 64,
    DEB_PATH: "e" * 64,
    RPM_PATH: "f" * 64,
}
OS_VERSIONS = {"Ubuntu": "24.04", "Fedora": "42", "Arch Linux": "2026-07-13"}
BROWSER_VERSIONS = {
    "Chromium": "138.0.7204.92",
    "Firefox": "140.0",
    "WebKitGTK": "2.48.3",
}


def candidate_manifest() -> dict[str, Any]:
    return {
        "schema_version": 2,
        "candidate": {
            "commit": CANDIDATE_COMMIT,
            "artifacts": [
                {
                    "path": path,
                    "size_bytes": 123,
                    "sha256": digest,
                }
                for path, digest in ARTIFACT_DIGESTS.items()
            ],
        },
        "system": {"fedora": "42", "arch": "2026-07-13"},
        "validation_targets": {
            "chromium": BROWSER_VERSIONS["Chromium"],
            "firefox": BROWSER_VERSIONS["Firefox"],
            "webkitgtk": BROWSER_VERSIONS["WebKitGTK"],
        },
        "required_evidence_ids": list(REQUIRED_EVIDENCE_IDS),
    }


def record_target(evidence_id: str) -> tuple[str, str, str]:
    if evidence_id.startswith("W1-"):
        _, os_name, browser_name = evidence_id.split("-")
        os_value = {"ubuntu": "Ubuntu", "fedora": "Fedora", "arch": "Arch Linux"}[
            os_name
        ]
        browser_value = {"chromium": "Chromium", "firefox": "Firefox"}[
            browser_name
        ]
        return os_value, browser_value, WEB_PATH
    if evidence_id.startswith("D1-"):
        _, os_name, package_type = evidence_id.split("-")
        os_value = {"ubuntu": "Ubuntu", "fedora": "Fedora", "arch": "Arch Linux"}[
            os_name
        ]
        artifact_path = {
            "appimage": APPIMAGE_PATH,
            "deb": DEB_PATH,
            "rpm": RPM_PATH,
        }[package_type]
        return os_value, "WebKitGTK", artifact_path
    if evidence_id == "C1-web":
        return "Ubuntu", "Chromium", WEB_PATH
    return "Ubuntu", "WebKitGTK", APPIMAGE_PATH


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
            ("missing-msb", "empty-msb", "corrupt-msb"), start=4
        )
    ]


def evidence_record(evidence_id: str = REQUIRED_EVIDENCE_IDS[0]) -> dict[str, Any]:
    os_name, browser_name, artifact_path = record_target(evidence_id)
    record = {
        "schema_version": 1,
        "id": evidence_id,
        "status": "PASS",
        "candidate_commit": CANDIDATE_COMMIT,
        "artifact": {
            "path": artifact_path,
            "sha256": ARTIFACT_DIGESTS[artifact_path],
        },
        "environment": {
            "os": os_name,
            "os_version": OS_VERSIONS[os_name],
            "kernel": "6.8.0-63-generic",
            "desktop_environment": "GNOME 46",
            "browser_or_webview": browser_name,
            "browser_or_webview_version": BROWSER_VERSIONS[browser_name],
            "gpu": "AMD Radeon RX 6800",
            "driver": "Mesa 25.1.3",
        },
        "tester": "Release Tester",
        "timestamp_utc": "2026-07-13T01:02:03Z",
        "executed_steps": [
            {
                "order": 1,
                "action": "Launch the retained artifact",
                "expected": "Application starts",
                "actual": "Application started",
                "result": "PASS",
            },
            {
                "order": 2,
                "action": "Save and restore progress",
                "expected": "State is restored",
                "actual": "State was restored",
                "result": "PASS",
            },
        ],
        "attachments": {
            "logs": ["public/logs/session.txt"],
            "screenshots": ["public/screenshots/restored.png"],
            "video": [],
        },
        "redacted_inspection": {
            "save": "Redacted save keys and state summary",
            "localStorage": "Redacted localStorage keys and state summary",
        },
        "public_evidence_sha256": PUBLIC_DIGEST,
        "raw_evidence_sha256": RAW_DIGEST,
        "redaction_statement": (
            "Public evidence excludes secrets, personal data, machine identifiers, "
            "and unredacted save contents."
        ),
    }
    if evidence_id.startswith("W1-"):
        record["negative_fixtures"] = negative_fixtures()
    return record


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def run_tool(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["python3", str(TOOL), *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


class ValidateRecordTests(unittest.TestCase):
    def assert_record_error(
        self, record: dict[str, Any], expected_error: str
    ) -> None:
        errors = validate_record(candidate_manifest(), record)
        self.assertIn(expected_error, errors)

    def test_accepts_complete_pass_record(self) -> None:
        self.assertEqual(validate_record(candidate_manifest(), evidence_record()), [])

    def test_rejects_wrong_schema_version_and_invalid_status(self) -> None:
        record = evidence_record()
        record["schema_version"] = 2
        record["status"] = "UNKNOWN"

        errors = validate_record(candidate_manifest(), record)

        self.assertIn("record.schema_version must be 1", errors)
        self.assertIn("record.status is invalid", errors)

    def test_rejects_missing_or_unknown_id(self) -> None:
        for value in (None, "W1-unknown-browser"):
            with self.subTest(value=value):
                record = evidence_record()
                if value is None:
                    del record["id"]
                else:
                    record["id"] = value
                self.assert_record_error(
                    record, "record.id is not a required evidence ID"
                )

    def test_rejects_wrong_candidate_sha(self) -> None:
        record = evidence_record()
        record["candidate_commit"] = "2" * 40

        self.assert_record_error(
            record, "record.candidate_commit must equal candidate commit"
        )

    def test_rejects_wrong_artifact_digest(self) -> None:
        record = evidence_record()
        record["artifact"]["sha256"] = "d" * 64

        self.assert_record_error(
            record, "record.artifact.sha256 must equal candidate artifact"
        )

    def test_rejects_artifact_path_not_retained_by_candidate(self) -> None:
        record = evidence_record()
        record["artifact"]["path"] = "artifact-from-another-build.zip"

        self.assert_record_error(
            record, "record.artifact.path must reference candidate artifact"
        )

    def test_w1_rejects_wrong_os_browser_or_non_web_artifact(self) -> None:
        mutations = (
            ("environment.os", "Fedora"),
            ("environment.os_version", "23.10"),
            ("environment.browser_or_webview", "Firefox"),
            ("environment.browser_or_webview_version", "137.0"),
            ("artifact.path", APPIMAGE_PATH),
        )
        for field, value in mutations:
            with self.subTest(field=field):
                record = evidence_record("W1-ubuntu-chromium")
                container, key = field.split(".")
                record[container][key] = value
                if field == "artifact.path":
                    record["artifact"]["sha256"] = ARTIFACT_DIGESTS[APPIMAGE_PATH]
                errors = validate_record(candidate_manifest(), record)
                self.assertTrue(
                    any(
                        error.startswith("record target does not match W1-")
                        for error in errors
                    ),
                    errors,
                )

    def test_d1_rejects_wrong_os_or_package_type(self) -> None:
        record = evidence_record("D1-fedora-rpm")
        record["environment"]["os"] = "Ubuntu"
        errors = validate_record(candidate_manifest(), record)
        self.assertTrue(
            any(
                error.startswith("record target does not match D1-")
                for error in errors
            ),
            errors,
        )

        record = evidence_record("D1-fedora-rpm")
        record["environment"]["os_version"] = "41"
        errors = validate_record(candidate_manifest(), record)
        self.assertTrue(
            any(
                error.startswith("record target does not match D1-")
                for error in errors
            ),
            errors,
        )

        record = evidence_record("D1-fedora-rpm")
        record["artifact"] = {
            "path": APPIMAGE_PATH,
            "sha256": ARTIFACT_DIGESTS[APPIMAGE_PATH],
        }
        errors = validate_record(candidate_manifest(), record)
        self.assertTrue(
            any(
                error.startswith("record target does not match D1-")
                for error in errors
            ),
            errors,
        )

    def test_c1_rejects_unsupported_web_and_desktop_combinations(self) -> None:
        web_record = evidence_record("C1-web")
        web_record["environment"]["browser_or_webview"] = "Google Chrome"
        errors = validate_record(candidate_manifest(), web_record)
        self.assertIn("record target is not an approved C1-web combination", errors)

        web_record = evidence_record("C1-web")
        web_record["environment"]["browser_or_webview_version"] = "137.0"
        errors = validate_record(candidate_manifest(), web_record)
        self.assertIn("record target is not an approved C1-web combination", errors)

        desktop_record = evidence_record("C1-desktop")
        desktop_record["environment"]["os"] = "Arch Linux"
        desktop_record["environment"]["os_version"] = OS_VERSIONS["Arch Linux"]
        desktop_record["artifact"] = {
            "path": DEB_PATH,
            "sha256": ARTIFACT_DIGESTS[DEB_PATH],
        }
        errors = validate_record(candidate_manifest(), desktop_record)
        self.assertIn(
            "record target is not an approved C1-desktop combination", errors
        )

    def test_w1_pass_requires_all_negative_fixture_provenance(self) -> None:
        record = evidence_record("W1-ubuntu-chromium")
        del record["negative_fixtures"]
        self.assert_record_error(
            record,
            (
                "record.negative_fixtures must contain missing-msb, empty-msb, "
                "and corrupt-msb"
            ),
        )

        mutations = (
            ("source_artifact.path", APPIMAGE_PATH),
            ("source_artifact.sha256", "9" * 64),
            ("transformation", "truncated-msb"),
            ("derived_artifact_sha256", ""),
        )
        for field, value in mutations:
            with self.subTest(field=field):
                record = evidence_record("W1-ubuntu-chromium")
                container, key = field.split(".") if "." in field else (None, field)
                fixture = record["negative_fixtures"][0]
                if container is None:
                    fixture[key] = value
                else:
                    fixture[container][key] = value
                errors = validate_record(candidate_manifest(), record)
                self.assertTrue(
                    any(
                        error.startswith("record.negative_fixtures[0]")
                        for error in errors
                    ),
                    errors,
                )

    def test_rejects_absolute_or_parent_public_references(self) -> None:
        mutations = (
            ("artifact", "path", "/tmp/release.zip"),
            ("attachments", "logs", ["../private/session.txt"]),
            ("attachments", "screenshots", ["/home/tester/screenshot.png"]),
        )
        for container, field, value in mutations:
            with self.subTest(container=container, field=field):
                candidate = candidate_manifest()
                record = evidence_record()
                record[container][field] = value
                if container == "artifact":
                    record["artifact"]["sha256"] = ARTIFACT_DIGESTS[WEB_PATH]
                errors = validate_record(candidate, record)
                self.assertTrue(
                    any("must be a public relative path" in error for error in errors),
                    errors,
                )

        record = evidence_record()
        record["negative_fixtures"][0]["source_artifact"]["path"] = "../web.zip"
        errors = validate_record(candidate_manifest(), record)
        self.assertTrue(
            any("must be a public relative path" in error for error in errors),
            errors,
        )

    def test_rejects_missing_or_empty_environment_fields(self) -> None:
        fields = (
            "os",
            "os_version",
            "kernel",
            "desktop_environment",
            "browser_or_webview",
            "browser_or_webview_version",
            "gpu",
            "driver",
        )
        for field in fields:
            for value in (None, ""):
                with self.subTest(field=field, value=value):
                    record = evidence_record()
                    if value is None:
                        del record["environment"][field]
                    else:
                        record["environment"][field] = value
                    self.assert_record_error(
                        record,
                        f"record.environment.{field} must be a non-empty string",
                    )

    def test_rejects_missing_or_empty_tester_and_utc_timestamp(self) -> None:
        for field in ("tester", "timestamp_utc"):
            for value in (None, ""):
                with self.subTest(field=field, value=value):
                    record = evidence_record()
                    if value is None:
                        del record[field]
                    else:
                        record[field] = value
                    self.assert_record_error(
                        record, f"record.{field} must be a non-empty string"
                    )

    def test_rejects_timestamp_that_is_not_utc(self) -> None:
        record = evidence_record()
        record["timestamp_utc"] = "2026-07-13T09:02:03+08:00"

        self.assert_record_error(
            record,
            "record.timestamp_utc must be an ISO 8601 UTC timestamp ending in Z",
        )

    def test_rejects_absent_or_empty_executed_steps(self) -> None:
        for value in (None, []):
            with self.subTest(value=value):
                record = evidence_record()
                if value is None:
                    del record["executed_steps"]
                else:
                    record["executed_steps"] = value
                self.assert_record_error(
                    record, "record.executed_steps must be a non-empty array"
                )

    def test_rejects_unordered_steps_and_missing_per_step_results(self) -> None:
        record = evidence_record()
        record["executed_steps"][1]["order"] = 3
        self.assert_record_error(
            record, "record.executed_steps orders must be consecutive starting at 1"
        )

        for field in ("action", "expected", "actual", "result"):
            with self.subTest(field=field):
                record = evidence_record()
                del record["executed_steps"][0][field]
                expected = (
                    "record.executed_steps[0].result is invalid"
                    if field == "result"
                    else f"record.executed_steps[0].{field} must be a non-empty string"
                )
                self.assert_record_error(record, expected)

    def test_pass_record_requires_every_step_to_pass(self) -> None:
        record = evidence_record()
        record["executed_steps"][1]["result"] = "FAIL"

        self.assert_record_error(
            record, "record with PASS status requires every step result to be PASS"
        )

    def test_rejects_absent_or_empty_logs_and_visual_evidence(self) -> None:
        record = evidence_record()
        record["attachments"]["logs"] = []
        self.assert_record_error(
            record, "record.attachments.logs must be a non-empty array"
        )

        record = evidence_record()
        record["attachments"]["screenshots"] = []
        record["attachments"]["video"] = []
        self.assert_record_error(
            record, "record.attachments must include a screenshot or video"
        )

        for field in ("logs", "screenshots", "video"):
            with self.subTest(field=field):
                record = evidence_record()
                del record["attachments"][field]
                self.assert_record_error(
                    record, f"record.attachments.{field} must be an array"
                )

    def test_rejects_absent_or_empty_save_and_localstorage_inspection(self) -> None:
        for field in ("save", "localStorage"):
            for value in (None, ""):
                with self.subTest(field=field, value=value):
                    record = evidence_record()
                    if value is None:
                        del record["redacted_inspection"][field]
                    else:
                        record["redacted_inspection"][field] = value
                    self.assert_record_error(
                        record,
                        (
                            f"record.redacted_inspection.{field} "
                            "must be a non-empty string"
                        ),
                    )

    def test_rejects_absent_or_invalid_public_and_raw_digests(self) -> None:
        for field in ("public_evidence_sha256", "raw_evidence_sha256"):
            for value in (None, ""):
                with self.subTest(field=field, value=value):
                    record = evidence_record()
                    if value is None:
                        del record[field]
                    else:
                        record[field] = value
                    errors = validate_record(candidate_manifest(), record)
                    self.assertTrue(
                        any(
                            error.startswith(f"record.{field} must be")
                            for error in errors
                        ),
                        errors,
                    )

    def test_rejects_absent_or_empty_redaction_statement(self) -> None:
        for value in (None, ""):
            with self.subTest(value=value):
                record = evidence_record()
                if value is None:
                    del record["redaction_statement"]
                else:
                    record["redaction_statement"] = value
                self.assert_record_error(
                    record,
                    "record.redaction_statement must be a non-empty string",
                )

    def test_validate_record_cli_reports_errors(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            candidate = root / "candidate.json"
            record_path = root / "record.json"
            write_json(candidate, candidate_manifest())
            record = evidence_record()
            del record["id"]
            write_json(record_path, record)

            result = run_tool("validate-record", str(candidate), str(record_path))

        self.assertEqual(result.returncode, 1)
        self.assertIn("record.id is not a required evidence ID", result.stderr)


class BuildIndexTests(unittest.TestCase):
    def build_records(self, records_dir: Path) -> None:
        for index, evidence_id in enumerate(REQUIRED_EVIDENCE_IDS):
            path = records_dir / f"{index:02d}-{evidence_id}.json"
            write_json(path, evidence_record(evidence_id))

    def run_build(
        self,
        root: Path,
        records_dir: Path,
        output: Path,
    ) -> subprocess.CompletedProcess[str]:
        candidate = root / "candidate.json"
        write_json(candidate, candidate_manifest())
        return run_tool(
            "build-index",
            "--candidate",
            str(candidate),
            "--records",
            str(records_dir),
            "--output",
            str(output),
        )

    def test_builds_complete_sorted_pass_index_with_exact_bindings(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            records_dir = root / "records"
            records_dir.mkdir()
            self.build_records(records_dir)
            output = root / "evidence-index.json"

            result = self.run_build(root, records_dir, output)
            index = json.loads(output.read_text(encoding="utf-8"))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(index["schema_version"], 1)
        self.assertEqual(index["candidate_commit"], CANDIDATE_COMMIT)
        self.assertEqual(index["aggregate_status"], "PASS")
        self.assertEqual(
            [item["id"] for item in index["records"]],
            list(REQUIRED_EVIDENCE_IDS),
        )
        self.assertEqual(len(index["records"]), 13)
        for item in index["records"]:
            self.assertEqual(item["candidate_commit"], CANDIDATE_COMMIT)
            expected_record = evidence_record(item["id"])
            self.assertEqual(item["artifact"], expected_record["artifact"])
            self.assertEqual(item["public_evidence_sha256"], PUBLIC_DIGEST)
            self.assertEqual(item["raw_evidence_sha256"], RAW_DIGEST)
            self.assertRegex(item["record_sha256"], r"^[0-9a-f]{64}$")
            if item["id"].startswith("W1-"):
                self.assertEqual(item.get("negative_fixtures"), negative_fixtures())
            else:
                self.assertNotIn("negative_fixtures", item)
        self.assertEqual(index["candidate_manifest"]["path"], "candidate.json")
        self.assertNotIn(temp_dir, json.dumps(index))

    def test_index_rejects_parent_reference_in_candidate_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            records_dir = root / "records"
            records_dir.mkdir()
            self.build_records(records_dir)
            candidate = candidate_manifest()
            candidate["candidate"]["artifacts"][0]["path"] = "../web.zip"
            candidate_path = root / "candidate.json"
            write_json(candidate_path, candidate)
            record_path = sorted(records_dir.iterdir())[0]
            record = json.loads(record_path.read_text(encoding="utf-8"))
            record["artifact"]["path"] = "../web.zip"
            record["negative_fixtures"] = negative_fixtures()
            for fixture in record["negative_fixtures"]:
                fixture["source_artifact"]["path"] = "../web.zip"
            write_json(record_path, record)
            output = root / "evidence-index.json"

            result = run_tool(
                "build-index",
                "--candidate",
                str(candidate_path),
                "--records",
                str(records_dir),
                "--output",
                str(output),
            )

            self.assertFalse(output.exists())
        self.assertEqual(result.returncode, 1)
        self.assertIn("must be a public relative path", result.stderr)

    def test_not_run_record_produces_not_run_aggregate(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            records_dir = root / "records"
            records_dir.mkdir()
            self.build_records(records_dir)
            first = next(records_dir.iterdir())
            record = json.loads(first.read_text(encoding="utf-8"))
            record["status"] = "NOT_RUN"
            record["executed_steps"][0]["result"] = "NOT_RUN"
            write_json(first, record)
            output = root / "evidence-index.json"

            result = self.run_build(root, records_dir, output)
            index = json.loads(output.read_text(encoding="utf-8"))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(index["aggregate_status"], "NOT_RUN")

    def test_rejects_missing_id(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            records_dir = root / "records"
            records_dir.mkdir()
            self.build_records(records_dir)
            next(records_dir.iterdir()).unlink()
            output = root / "evidence-index.json"

            result = self.run_build(root, records_dir, output)
            self.assertFalse(output.exists())

        self.assertEqual(result.returncode, 1)
        self.assertIn("missing required evidence IDs", result.stderr)

    def test_rejects_duplicate_id(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            records_dir = root / "records"
            records_dir.mkdir()
            self.build_records(records_dir)
            write_json(records_dir / "duplicate.json", evidence_record())
            output = root / "evidence-index.json"

            result = self.run_build(root, records_dir, output)
            self.assertFalse(output.exists())

        self.assertEqual(result.returncode, 1)
        self.assertIn("duplicate evidence ID", result.stderr)

    def test_rejects_unknown_id(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            records_dir = root / "records"
            records_dir.mkdir()
            self.build_records(records_dir)
            unknown = evidence_record()
            unknown["id"] = "W1-unknown"
            write_json(records_dir / "unknown.json", unknown)
            output = root / "evidence-index.json"

            result = self.run_build(root, records_dir, output)
            self.assertFalse(output.exists())

        self.assertEqual(result.returncode, 1)
        self.assertIn("record.id is not a required evidence ID", result.stderr)

    def test_index_is_immutable(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            records_dir = root / "records"
            records_dir.mkdir()
            self.build_records(records_dir)
            output = root / "evidence-index.json"
            output.write_text("keep\n", encoding="utf-8")

            result = self.run_build(root, records_dir, output)

            self.assertEqual(output.read_text(encoding="utf-8"), "keep\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("immutable evidence index already exists", result.stderr)


if __name__ == "__main__":
    unittest.main()
