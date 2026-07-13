#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Any

from release_schema import (
    REQUIRED_EVIDENCE_IDS,
    read_object,
    sha256_file,
    validate_sha256,
)


STATUSES = {"PASS", "FAIL", "BLOCKED", "NOT_RUN"}
NEGATIVE_FIXTURE_TRANSFORMATIONS = {"missing-msb", "empty-msb", "corrupt-msb"}
OS_NAMES = {"ubuntu": "Ubuntu", "fedora": "Fedora", "arch": "Arch Linux"}
BROWSER_NAMES = {"chromium": "Chromium", "firefox": "Firefox"}


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


def require_non_empty_array(value: Any, path: str, errors: list[str]) -> list[Any]:
    if not isinstance(value, list) or not value:
        errors.append(f"{path} must be a non-empty array")
        return []
    return value


def require_non_empty_string(value: Any, path: str, errors: list[str]) -> str:
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{path} must be a non-empty string")
        return ""
    return value


def validate_public_reference(value: Any, path: str, errors: list[str]) -> str:
    text = require_non_empty_string(value, path, errors)
    if not text:
        return ""
    posix = PurePosixPath(text)
    windows = PureWindowsPath(text)
    if (
        posix.is_absolute()
        or windows.is_absolute()
        or ".." in posix.parts
        or ".." in windows.parts
    ):
        errors.append(f"{path} must be a public relative path without '..'")
    return text


def validate_utc_timestamp(value: Any, path: str, errors: list[str]) -> None:
    text = require_non_empty_string(value, path, errors)
    if not text:
        return
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        parsed = None
    if (
        not text.endswith("Z")
        or parsed is None
        or parsed.utcoffset() != timezone.utc.utcoffset(parsed)
    ):
        errors.append(f"{path} must be an ISO 8601 UTC timestamp ending in Z")


def candidate_commit(candidate: dict[str, Any]) -> str:
    candidate_identity = candidate.get("candidate")
    if not isinstance(candidate_identity, dict):
        return ""
    commit = candidate_identity.get("commit")
    return commit if isinstance(commit, str) else ""


def candidate_artifacts(candidate: dict[str, Any]) -> dict[str, str]:
    candidate_identity = candidate.get("candidate")
    if not isinstance(candidate_identity, dict):
        return {}
    artifacts = candidate_identity.get("artifacts")
    if not isinstance(artifacts, list):
        return {}
    result: dict[str, str] = {}
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            continue
        path = artifact.get("path")
        digest = artifact.get("sha256")
        if isinstance(path, str) and isinstance(digest, str):
            result[path] = digest
    return result


def candidate_version(candidate: dict[str, Any], group: str, key: str) -> str:
    values = candidate.get(group)
    if not isinstance(values, dict):
        return ""
    value = values.get(key)
    return value if isinstance(value, str) else ""


def artifact_kind(path: str) -> str:
    name = PurePosixPath(path).name.lower()
    if name.endswith(".appimage"):
        return "appimage"
    if name.endswith(".deb"):
        return "deb"
    if name.endswith(".rpm"):
        return "rpm"
    if name.endswith(".zip") and "web" in name:
        return "web"
    return ""


def expected_os_version(candidate: dict[str, Any], os_name: str) -> str:
    if os_name == "Ubuntu":
        return "24.04"
    if os_name == "Fedora":
        return candidate_version(candidate, "system", "fedora")
    if os_name == "Arch Linux":
        return candidate_version(candidate, "system", "arch")
    return ""


def expected_browser_version(candidate: dict[str, Any], browser: str) -> str:
    key = {
        "Chromium": "chromium",
        "Firefox": "firefox",
        "WebKitGTK": "webkitgtk",
    }.get(browser, "")
    return candidate_version(candidate, "validation_targets", key) if key else ""


def record_target_matches(
    candidate: dict[str, Any],
    evidence_id: Any,
    environment: dict[str, Any],
    artifact_path: str,
) -> bool:
    os_name = environment.get("os")
    os_version = environment.get("os_version")
    browser = environment.get("browser_or_webview")
    browser_version = environment.get("browser_or_webview_version")
    kind = artifact_kind(artifact_path)
    if not isinstance(evidence_id, str):
        return False
    if evidence_id.startswith("W1-"):
        _, os_key, browser_key = evidence_id.split("-")
        expected_os = OS_NAMES[os_key]
        expected_browser = BROWSER_NAMES[browser_key]
        return (
            os_name == expected_os
            and os_version == expected_os_version(candidate, expected_os)
            and browser == expected_browser
            and browser_version == expected_browser_version(candidate, expected_browser)
            and kind == "web"
        )
    if evidence_id.startswith("D1-"):
        _, os_key, package_kind = evidence_id.split("-")
        expected_os = OS_NAMES[os_key]
        return (
            os_name == expected_os
            and os_version == expected_os_version(candidate, expected_os)
            and browser == "WebKitGTK"
            and browser_version == expected_browser_version(candidate, "WebKitGTK")
            and kind == package_kind
        )
    if evidence_id == "C1-web":
        return (
            os_name in OS_NAMES.values()
            and os_version == expected_os_version(candidate, os_name)
            and browser in BROWSER_NAMES.values()
            and browser_version == expected_browser_version(candidate, browser)
            and kind == "web"
        )
    if evidence_id == "C1-desktop":
        supported_packages = {
            "Ubuntu": {"appimage", "deb"},
            "Fedora": {"appimage", "rpm"},
            "Arch Linux": {"appimage"},
        }
        return (
            os_name in supported_packages
            and os_version == expected_os_version(candidate, os_name)
            and browser == "WebKitGTK"
            and browser_version == expected_browser_version(candidate, "WebKitGTK")
            and kind in supported_packages.get(os_name, set())
        )
    return False


def validate_string_array(value: Any, path: str, errors: list[str]) -> list[Any]:
    items = require_array(value, path, errors)
    for index, item in enumerate(items):
        validate_public_reference(item, f"{path}[{index}]", errors)
    return items


def validate_negative_fixtures(
    candidate: dict[str, Any], record: dict[str, Any], errors: list[str]
) -> None:
    fixtures = require_array(
        record.get("negative_fixtures"), "record.negative_fixtures", errors
    )
    transformations: list[Any] = []
    artifacts = candidate_artifacts(candidate)
    for index, raw_fixture in enumerate(fixtures):
        path = f"record.negative_fixtures[{index}]"
        fixture = require_object(raw_fixture, path, errors)
        source = require_object(
            fixture.get("source_artifact"), f"{path}.source_artifact", errors
        )
        source_path = validate_public_reference(
            source.get("path"), f"{path}.source_artifact.path", errors
        )
        source_digest = validate_sha256(
            source.get("sha256"), f"{path}.source_artifact.sha256", errors
        )
        if source_path and (
            artifact_kind(source_path) != "web" or source_path not in artifacts
        ):
            errors.append(
                f"{path}.source_artifact.path must reference candidate Web ZIP"
            )
        elif (
            source_path
            and source_digest
            and source_digest != artifacts.get(source_path)
        ):
            errors.append(
                f"{path}.source_artifact.sha256 must equal candidate Web artifact"
            )
        transformation = fixture.get("transformation")
        transformations.append(transformation)
        if transformation not in NEGATIVE_FIXTURE_TRANSFORMATIONS:
            errors.append(f"{path}.transformation is invalid")
        validate_sha256(
            fixture.get("derived_artifact_sha256"),
            f"{path}.derived_artifact_sha256",
            errors,
        )
    if (
        len(fixtures) != len(NEGATIVE_FIXTURE_TRANSFORMATIONS)
        or set(transformations) != NEGATIVE_FIXTURE_TRANSFORMATIONS
    ):
        errors.append(
            "record.negative_fixtures must contain missing-msb, empty-msb, "
            "and corrupt-msb"
        )


def validate_record(
    candidate: dict[str, Any], record: dict[str, Any]
) -> list[str]:
    errors: list[str] = []
    if record.get("schema_version") != 1:
        errors.append("record.schema_version must be 1")
    if record.get("id") not in REQUIRED_EVIDENCE_IDS:
        errors.append("record.id is not a required evidence ID")

    expected_commit = candidate_commit(candidate)
    if record.get("candidate_commit") != expected_commit:
        errors.append("record.candidate_commit must equal candidate commit")

    status = record.get("status")
    if status not in STATUSES:
        errors.append("record.status is invalid")

    artifact = require_object(record.get("artifact"), "record.artifact", errors)
    artifact_path = validate_public_reference(
        artifact.get("path"), "record.artifact.path", errors
    )
    artifact_digest = validate_sha256(
        artifact.get("sha256"), "record.artifact.sha256", errors
    )
    artifacts = candidate_artifacts(candidate)
    if artifact_path and artifact_path not in artifacts:
        errors.append("record.artifact.path must reference candidate artifact")
    elif (
        artifact_path
        and artifact_digest
        and artifact_digest != artifacts.get(artifact_path)
    ):
        errors.append("record.artifact.sha256 must equal candidate artifact")

    environment = require_object(
        record.get("environment"), "record.environment", errors
    )
    for field in (
        "os",
        "os_version",
        "kernel",
        "desktop_environment",
        "browser_or_webview",
        "browser_or_webview_version",
        "gpu",
        "driver",
    ):
        require_non_empty_string(
            environment.get(field), f"record.environment.{field}", errors
        )

    evidence_id = record.get("id")
    if evidence_id in REQUIRED_EVIDENCE_IDS and not record_target_matches(
        candidate, evidence_id, environment, artifact_path
    ):
        if isinstance(evidence_id, str) and evidence_id.startswith(("W1-", "D1-")):
            errors.append(f"record target does not match {evidence_id}")
        else:
            errors.append(f"record target is not an approved {evidence_id} combination")

    if (
        isinstance(evidence_id, str)
        and evidence_id.startswith("W1-")
        and (status == "PASS" or "negative_fixtures" in record)
    ):
        validate_negative_fixtures(candidate, record, errors)

    require_non_empty_string(record.get("tester"), "record.tester", errors)
    validate_utc_timestamp(record.get("timestamp_utc"), "record.timestamp_utc", errors)

    steps = require_non_empty_array(
        record.get("executed_steps"), "record.executed_steps", errors
    )
    orders: list[int] = []
    step_results: list[Any] = []
    for index, raw_step in enumerate(steps):
        path = f"record.executed_steps[{index}]"
        step = require_object(raw_step, path, errors)
        order = step.get("order")
        if not isinstance(order, int) or isinstance(order, bool) or order < 1:
            errors.append(f"{path}.order must be a positive integer")
        else:
            orders.append(order)
        for field in ("action", "expected", "actual"):
            require_non_empty_string(step.get(field), f"{path}.{field}", errors)
        result = step.get("result")
        step_results.append(result)
        if result not in STATUSES:
            errors.append(f"{path}.result is invalid")
    if orders and orders != list(range(1, len(steps) + 1)):
        errors.append(
            "record.executed_steps orders must be consecutive starting at 1"
        )
    if status == "PASS" and any(result != "PASS" for result in step_results):
        errors.append(
            "record with PASS status requires every step result to be PASS"
        )

    attachments = require_object(
        record.get("attachments"), "record.attachments", errors
    )
    logs = validate_string_array(
        attachments.get("logs"), "record.attachments.logs", errors
    )
    screenshots = validate_string_array(
        attachments.get("screenshots"), "record.attachments.screenshots", errors
    )
    video = validate_string_array(
        attachments.get("video"), "record.attachments.video", errors
    )
    if isinstance(attachments.get("logs"), list) and not logs:
        errors.append("record.attachments.logs must be a non-empty array")
    if (
        isinstance(attachments.get("screenshots"), list)
        and isinstance(attachments.get("video"), list)
        and not screenshots
        and not video
    ):
        errors.append("record.attachments must include a screenshot or video")

    inspection = require_object(
        record.get("redacted_inspection"), "record.redacted_inspection", errors
    )
    for field in ("save", "localStorage"):
        require_non_empty_string(
            inspection.get(field), f"record.redacted_inspection.{field}", errors
        )

    validate_sha256(
        record.get("public_evidence_sha256"),
        "record.public_evidence_sha256",
        errors,
    )
    validate_sha256(
        record.get("raw_evidence_sha256"),
        "record.raw_evidence_sha256",
        errors,
    )
    require_non_empty_string(
        record.get("redaction_statement"), "record.redaction_statement", errors
    )
    return errors


def aggregate_status(statuses: list[str]) -> str:
    if all(status == "PASS" for status in statuses):
        return "PASS"
    if "FAIL" in statuses:
        return "FAIL"
    if "BLOCKED" in statuses:
        return "BLOCKED"
    return "NOT_RUN"


def validate_record_command(args: argparse.Namespace) -> int:
    try:
        candidate = read_object(args.candidate, "candidate manifest")
        record = read_object(args.record, "evidence record")
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    errors = validate_record(candidate, record)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"OK: valid evidence record {record['id']}")
    return 0


def build_index(args: argparse.Namespace) -> int:
    try:
        candidate = read_object(args.candidate, "candidate manifest")
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    try:
        record_paths = sorted(args.records.glob("*.json"))
    except OSError as error:
        print(f"error: cannot list evidence records: {error}", file=sys.stderr)
        return 1

    loaded: list[tuple[Path, dict[str, Any]]] = []
    errors: list[str] = []
    seen: set[str] = set()
    duplicate_ids: set[str] = set()
    for path in record_paths:
        try:
            record = read_object(path, f"evidence record {path}")
        except ValueError as error:
            errors.append(str(error))
            continue
        record_errors = validate_record(candidate, record)
        errors.extend(f"{path}: {error}" for error in record_errors)
        evidence_id = record.get("id")
        if isinstance(evidence_id, str):
            if evidence_id in seen:
                duplicate_ids.add(evidence_id)
            seen.add(evidence_id)
        loaded.append((path, record))

    for evidence_id in sorted(duplicate_ids):
        errors.append(f"duplicate evidence ID: {evidence_id}")
    missing = [
        evidence_id
        for evidence_id in REQUIRED_EVIDENCE_IDS
        if evidence_id not in seen
    ]
    if missing:
        errors.append(f"missing required evidence IDs: {', '.join(missing)}")
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    by_id = {record["id"]: (path, record) for path, record in loaded}
    records = []
    statuses: list[str] = []
    for evidence_id in REQUIRED_EVIDENCE_IDS:
        path, record = by_id[evidence_id]
        status = record["status"]
        statuses.append(status)
        records.append(
            {
                "id": evidence_id,
                "status": status,
                "candidate_commit": record["candidate_commit"],
                "artifact": record["artifact"],
                "record_path": path.name,
                "record_sha256": sha256_file(path),
                "public_evidence_sha256": record["public_evidence_sha256"],
                "raw_evidence_sha256": record["raw_evidence_sha256"],
                **(
                    {"negative_fixtures": record["negative_fixtures"]}
                    if evidence_id.startswith("W1-")
                    and "negative_fixtures" in record
                    else {}
                ),
            }
        )

    index = {
        "schema_version": 1,
        "candidate_commit": candidate_commit(candidate),
        "candidate_manifest": {
            "path": args.candidate.name,
            "sha256": sha256_file(args.candidate),
        },
        "aggregate_status": aggregate_status(statuses),
        "records": records,
    }
    encoded = (json.dumps(index, indent=2, sort_keys=True) + "\n").encode("utf-8")
    try:
        descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(encoded)
    except FileExistsError:
        print(
            f"error: immutable evidence index already exists: {args.output}",
            file=sys.stderr,
        )
        return 1
    except OSError as error:
        print(f"error: cannot create evidence index: {error}", file=sys.stderr)
        return 1
    print(f"created immutable evidence index: {args.output}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate release evidence records and build an immutable index."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate = subparsers.add_parser("validate-record")
    validate.add_argument("candidate", type=Path)
    validate.add_argument("record", type=Path)
    validate.set_defaults(handler=validate_record_command)
    build = subparsers.add_parser("build-index")
    build.add_argument("--candidate", required=True, type=Path)
    build.add_argument("--records", required=True, type=Path)
    build.add_argument("--output", required=True, type=Path)
    build.set_defaults(handler=build_index)
    args = parser.parse_args()
    return args.handler(args)


if __name__ == "__main__":
    raise SystemExit(main())
