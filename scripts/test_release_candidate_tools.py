from __future__ import annotations

import io
import json
import shutil
import subprocess
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BENCHMARK = ROOT / "scripts" / "benchmark_report.py"
BUILDER = ROOT / "scripts" / "build_release_artifacts.sh"
REPRO = ROOT / "scripts" / "compare_reproducible_builds.py"
REPRO_POLICY = ROOT / "scripts" / "reproducibility-normalization-v1.json"
RC = ROOT / "scripts" / "rc_manifest.py"
EVIDENCE_TEMPLATE = ROOT / "scripts" / "release-evidence-template.json"
SHA = "1" * 40


def run_script(script: Path, *args: str, cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["python3", str(script), *args],
        cwd=cwd,
        text=True,
        capture_output=True,
        check=False,
    )


def ar_archive(members: list[tuple[str, bytes, int]]) -> bytes:
    output = bytearray(b"!<arch>\n")
    for name, data, timestamp in members:
        header = (
            f"{name + '/':<16}{timestamp:<12}{0:<6}{0:<6}{0o100644:<8o}"
            f"{len(data):<10}`\n"
        ).encode("ascii")
        output.extend(header)
        output.extend(data)
        if len(data) % 2:
            output.extend(b"\n")
    return bytes(output)


def tar_gz(files: dict[str, bytes], *, timestamp: int) -> bytes:
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz") as archive:
        for name, data in sorted(files.items()):
            info = tarfile.TarInfo(name)
            info.mode = 0o755 if name.endswith("/moonsight") else 0o644
            info.mtime = timestamp
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))
    return output.getvalue()


def write_deb(path: Path, files: dict[str, bytes], *, timestamp: int) -> None:
    control = tar_gz(
        {"control": b"Package: moonsight\nVersion: 1.0.0\nArchitecture: amd64\n"},
        timestamp=timestamp,
    )
    data = tar_gz(files, timestamp=timestamp)
    path.write_bytes(
        ar_archive(
            [
                ("debian-binary", b"2.0\n", timestamp),
                ("control.tar.gz", control, timestamp),
                ("data.tar.gz", data, timestamp),
            ]
        )
    )


def benchmark_input() -> dict[str, object]:
    runs: list[dict[str, object]] = []
    for index in range(5):
        runs.append(
            {
                "id": f"warm-{index}",
                "mode": "warm",
                "warmed_up": True,
                "samples_ms": [10.0] * 1000,
            }
        )
        runs.append(
            {
                "id": f"cold-{index}",
                "mode": "cold",
                "fresh_sessions": True,
                "samples_ms": [80.0] * 100,
                "catalog_decode_ms": [20.0] * 100,
                "first_gpu_glyph_upload_ms": [10.0] * 100,
            }
        )
    return {
        "schema_version": 1,
        "environment": {
            "os": "test",
            "cpu": "test-cpu",
            "ram": "16 GiB",
            "browser_or_webview": "test-browser",
            "gpu_driver": "test-gpu",
            "toolchains": {"moon": "test"},
            "power_mode": "performance",
            "viewport": "1280x720",
            "demo_trace": "demo-10m",
        },
        "runs": runs,
        "memory": {
            "decoded_catalogs_mib": 31.0,
            "catalogs_rollback_incremental_mib": 47.0,
            "rollback_checkpoints": 64,
        },
        "frame": {"baseline_p95_ms": 10.0, "candidate_p95_ms": 10.4},
    }


class BenchmarkReportTests(unittest.TestCase):
    def test_reports_five_run_median_p95_and_frozen_gates(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            input_path = Path(temp) / "samples.json"
            output_path = Path(temp) / "report.json"
            input_path.write_text(json.dumps(benchmark_input()), encoding="utf-8")

            result = run_script(BENCHMARK, str(input_path), "--output", str(output_path))

            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(report["outcome"], "PASS")
            self.assertEqual(report["metrics"]["warm_locale_switch_ms"]["median_run_p95"], 10.0)
            self.assertEqual(report["metrics"]["cold_locale_switch_ms"]["median_run_p95"], 80.0)
            self.assertEqual(report["metrics"]["cold_catalog_decode_ms"]["median_run_p95"], 20.0)
            self.assertEqual(report["metrics"]["cold_first_gpu_glyph_upload_ms"]["median_run_p95"], 10.0)
            self.assertAlmostEqual(report["metrics"]["rendered_frame_regression_percent"]["value"], 4.0)

    def test_rejects_unretained_or_incomplete_sample_sets(self) -> None:
        data = benchmark_input()
        data["runs"][0]["samples_ms"] = [10.0] * 999  # type: ignore[index]
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "samples.json"
            path.write_text(json.dumps(data), encoding="utf-8")

            result = run_script(BENCHMARK, str(path))

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("exactly 1000 samples", result.stderr)


class ReproducibilityTests(unittest.TestCase):
    def test_builder_rejects_wrong_version_and_dirty_worktree(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp) / "repo"
            scripts = repo / "scripts"
            scripts.mkdir(parents=True)
            shutil.copy2(BUILDER, scripts / BUILDER.name)
            for name in ("publish-web.sh", "publish-desktop.sh"):
                path = scripts / name
                path.write_text("#!/usr/bin/env bash\nexit 99\n", encoding="utf-8")
                path.chmod(0o755)
            subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
            subprocess.run(
                ["git", "config", "user.email", "test@example.com"], cwd=repo, check=True
            )
            subprocess.run(["git", "config", "user.name", "Test"], cwd=repo, check=True)
            subprocess.run(["git", "add", "scripts"], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-qm", "fixture"], cwd=repo, check=True)

            wrong_version = subprocess.run(
                [
                    "bash",
                    str(scripts / BUILDER.name),
                    "--version",
                    "v2.0.0",
                    "--out",
                    str(repo / "wrong-version"),
                ],
                cwd=repo,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertNotEqual(wrong_version.returncode, 0)
            self.assertIn("error: expected v1.0.0", wrong_version.stderr)

            (repo / "dirty.txt").write_text("dirty\n", encoding="utf-8")
            dirty = subprocess.run(
                [
                    "bash",
                    str(scripts / BUILDER.name),
                    "--version",
                    "v1.0.0",
                    "--out",
                    str(repo / "dirty"),
                ],
                cwd=repo,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertNotEqual(dirty.returncode, 0)
            self.assertIn("error: dirty worktree", dirty.stderr)

    def test_builder_writes_exact_candidate_and_comparison_sets(self) -> None:
        if not BUILDER.exists():
            self.fail("release artifact builder is missing")
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp) / "repo"
            scripts = repo / "scripts"
            scripts.mkdir(parents=True)
            shutil.copy2(BUILDER, scripts / BUILDER.name)
            (scripts / "publish-web.sh").write_text(
                """#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$2/assets"
printf 'same web payload\\n' > "$2/index.html"
printf 'same wasm payload\\n' > "$2/assets/moonsight.wasm"
""",
                encoding="utf-8",
            )
            (scripts / "publish-desktop.sh").write_text(
                """#!/usr/bin/env bash
set -euo pipefail
version="${MOONSIGHT_RELEASE_VERSION#v}"
target="${CARGO_TARGET_DIR:?}/release/bundle"
mkdir -p "$target/appimage" "$target/deb" "$target/rpm"
printf 'appimage container %s\\n' "${MOONSIGHT_BUILD_NUMBER:?}" > "$target/appimage/MoonSight_${version}_amd64.AppImage"
printf 'deb container %s\\n' "${MOONSIGHT_BUILD_NUMBER:?}" > "$target/deb/MoonSight_${version}_amd64.deb"
printf 'rpm container %s\\n' "${MOONSIGHT_BUILD_NUMBER:?}" > "$target/rpm/MoonSight-${version}-1.x86_64.rpm"
""",
                encoding="utf-8",
            )
            for script in scripts.iterdir():
                script.chmod(0o755)
            subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
            subprocess.run(
                ["git", "config", "user.email", "test@example.com"], cwd=repo, check=True
            )
            subprocess.run(["git", "config", "user.name", "Test"], cwd=repo, check=True)
            subprocess.run(["git", "add", "scripts"], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-qm", "fixture"], cwd=repo, check=True)
            release = repo / "release"

            result = subprocess.run(
                [
                    "bash",
                    str(scripts / BUILDER.name),
                    "--version",
                    "v1.0.0",
                    "--out",
                    str(release),
                ],
                cwd=repo,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            artifact_names = {
                "moonsight-web-x86_64-v1.0.0.zip",
                "moonsight-linux-x86_64-v1.0.0.AppImage",
                "moonsight-linux-x86_64-v1.0.0.deb",
                "moonsight-linux-x86_64-v1.0.0.rpm",
            }
            self.assertEqual(
                {path.name for path in (release / "first").iterdir()},
                artifact_names | {"SHA256SUMS", "build-metadata.json"},
            )
            self.assertEqual(
                {path.name for path in (release / "second").iterdir()},
                artifact_names | {"build-metadata.json"},
            )
            self.assertFalse((release / "second" / "SHA256SUMS").exists())
            web_name = "moonsight-web-x86_64-v1.0.0.zip"
            self.assertEqual(
                (release / "first" / web_name).read_bytes(),
                (release / "second" / web_name).read_bytes(),
            )
            first_metadata = json.loads(
                (release / "first" / "build-metadata.json").read_text(encoding="utf-8")
            )
            second_metadata = json.loads(
                (release / "second" / "build-metadata.json").read_text(encoding="utf-8")
            )
            self.assertEqual(first_metadata["build_number"], 1)
            self.assertEqual(second_metadata["build_number"], 2)
            self.assertTrue(first_metadata["release_candidate"])
            self.assertFalse(second_metadata["release_candidate"])
            self.assertEqual(
                [item["path"] for item in first_metadata["artifacts"]],
                sorted(artifact_names),
            )

    def test_web_zip_requires_raw_byte_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            left, right = root / "left", root / "right"
            left.mkdir()
            right.mkdir()
            name = "moonsight-web-x86_64-v1.0.0.zip"
            for directory, comment in ((left, b"first"), (right, b"second")):
                with zipfile.ZipFile(directory / name, "w") as archive:
                    archive.comment = comment
                    archive.writestr("index.html", "same payload")

            result = run_script(
                REPRO,
                str(left),
                str(right),
                "--allowlist",
                str(REPRO_POLICY),
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn(f"web ZIP differs in raw bytes: {name}", result.stderr)

    def test_desktop_packages_compare_normalized_extracted_payloads(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            left, right = root / "left", root / "right"
            left.mkdir()
            right.mkdir()
            name = "moonsight-linux-x86_64-v1.0.0.deb"
            payload = {
                "usr/bin/moonsight": b"same executable",
                "usr/lib/moonsight/game.msb": b"MSB2same",
                "usr/lib/moonsight/app.js": b"same javascript",
            }
            write_deb(left / name, payload, timestamp=1_700_000_000)
            write_deb(right / name, payload, timestamp=1_800_000_000)
            report_path = root / "report.json"

            result = run_script(
                REPRO,
                str(left),
                str(right),
                "--allowlist",
                str(REPRO_POLICY),
                "--output",
                str(report_path),
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertRegex(str(report.get("input_sha256", "")), r"^[0-9a-f]{64}$")
            artifact = report["artifacts"][0]
            self.assertEqual(artifact["left_size_bytes"], (left / name).stat().st_size)
            self.assertEqual(artifact["right_size_bytes"], (right / name).stat().st_size)
            self.assertNotEqual(artifact["left_raw_sha256"], artifact["right_raw_sha256"])
            self.assertEqual(
                artifact["left_normalized_sha256"],
                artifact["right_normalized_sha256"],
            )
            self.assertEqual(artifact["comparison"], "normalized-desktop-payload")

    def test_desktop_payload_rejects_unexplained_core_difference(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            left, right = root / "left", root / "right"
            left.mkdir()
            right.mkdir()
            name = "moonsight-linux-x86_64-v1.0.0.deb"
            write_deb(
                left / name,
                {"usr/lib/moonsight/app.js": b"left javascript"},
                timestamp=1_700_000_000,
            )
            write_deb(
                right / name,
                {"usr/lib/moonsight/app.js": b"right javascript"},
                timestamp=1_800_000_000,
            )

            result = run_script(
                REPRO,
                str(left),
                str(right),
                "--allowlist",
                str(REPRO_POLICY),
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                "desktop payload differs in raw bytes: usr/lib/moonsight/app.js",
                result.stderr,
            )

    def test_desktop_payload_never_normalizes_extensionless_executables(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            left, right = root / "left", root / "right"
            left.mkdir()
            right.mkdir()
            name = "moonsight-linux-x86_64-v1.0.0.deb"
            write_deb(
                left / name,
                {"usr/bin/moonsight": b"build=1\n"},
                timestamp=1_700_000_000,
            )
            write_deb(
                right / name,
                {"usr/bin/moonsight": b"build=2\n"},
                timestamp=1_800_000_000,
            )
            policy = json.loads(REPRO_POLICY.read_text(encoding="utf-8"))
            policy["entries"] = [
                {
                    "id": "forbidden-executable-normalization",
                    "artifact_glob": "usr/bin/moonsight",
                    "byte_range": {"start": 6, "end": 7},
                    "replacement_utf8": "0",
                    "rationale": "test-only attempted executable exclusion",
                    "owner": "test",
                }
            ]
            policy_path = root / "policy.json"
            policy_path.write_text(json.dumps(policy), encoding="utf-8")

            result = run_script(
                REPRO,
                str(left),
                str(right),
                "--allowlist",
                str(policy_path),
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                "desktop payload differs in raw bytes: usr/bin/moonsight",
                result.stderr,
            )

    def test_desktop_payload_never_normalizes_web_resources(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            left, right = root / "left", root / "right"
            left.mkdir()
            right.mkdir()
            name = "moonsight-linux-x86_64-v1.0.0.deb"
            resource = "usr/lib/moonsight/assets/app.css"
            write_deb(left / name, {resource: b"color:1\n"}, timestamp=1_700_000_000)
            write_deb(right / name, {resource: b"color:2\n"}, timestamp=1_800_000_000)
            policy = json.loads(REPRO_POLICY.read_text(encoding="utf-8"))
            policy["entries"] = [
                {
                    "id": "forbidden-resource-normalization",
                    "artifact_glob": resource,
                    "byte_range": {"start": 6, "end": 7},
                    "replacement_utf8": "0",
                    "rationale": "test-only attempted resource exclusion",
                    "owner": "test",
                }
            ]
            policy_path = root / "policy.json"
            policy_path.write_text(json.dumps(policy), encoding="utf-8")

            result = run_script(
                REPRO,
                str(left),
                str(right),
                "--allowlist",
                str(policy_path),
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                f"desktop payload differs in raw bytes: {resource}",
                result.stderr,
            )

    def test_retains_raw_digests_and_allows_only_declared_normalization(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            left, right = root / "left", root / "right"
            left.mkdir()
            right.mkdir()
            (left / "game.msb").write_bytes(b"MSB2same")
            (right / "game.msb").write_bytes(b"MSB2same")
            (left / "build.txt").write_bytes(b"time=1111\npayload=same\n")
            (right / "build.txt").write_bytes(b"time=2222\npayload=same\n")
            allowlist = {
                "schema_version": 1,
                "entries": [
                    {
                        "id": "build-time",
                        "artifact_glob": "build.txt",
                        "byte_range": {"start": 5, "end": 9},
                        "replacement_utf8": "0000",
                        "rationale": "packager timestamp",
                        "owner": "release engineering",
                    }
                ],
            }
            allow_path = root / "allow.json"
            report_path = root / "report.json"
            allow_path.write_text(json.dumps(allowlist), encoding="utf-8")

            result = run_script(
                REPRO,
                str(left),
                str(right),
                "--allowlist",
                str(allow_path),
                "--output",
                str(report_path),
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(report_path.read_text(encoding="utf-8"))
            artifact = next(item for item in report["artifacts"] if item["path"] == "build.txt")
            self.assertNotEqual(artifact["left_raw_sha256"], artifact["right_raw_sha256"])
            self.assertEqual(artifact["left_normalized_sha256"], artifact["right_normalized_sha256"])
            self.assertEqual(artifact["normalization_id"], "build-time")

    def test_unknown_or_core_artifact_difference_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            left, right = root / "left", root / "right"
            left.mkdir()
            right.mkdir()
            (left / "game.msb").write_bytes(b"MSB2left")
            (right / "game.msb").write_bytes(b"MSB2right")
            allow_path = root / "allow.json"
            allow_path.write_text(json.dumps({"schema_version": 1, "entries": []}), encoding="utf-8")

            result = run_script(REPRO, str(left), str(right), "--allowlist", str(allow_path))

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("core artifact differs in raw bytes: game.msb", result.stderr)


class RcManifestTests(unittest.TestCase):
    def write_inputs(
        self,
        root: Path,
        *,
        benchmark_outcome: str = "PASS",
    ) -> tuple[Path, Path, Path, Path]:
        benchmark = root / "benchmark.json"
        repro = root / "repro.json"
        metadata = root / "metadata.json"
        output = root / "rc.json"
        benchmark.write_text(
            json.dumps(
                {
                    "outcome": benchmark_outcome,
                    "input_sha256": "a" * 64,
                }
            ),
            encoding="utf-8",
        )
        repro.write_text(
            json.dumps(
                {
                    "outcome": "PASS",
                    "input_sha256": "b" * 64,
                    "artifacts": [
                        {
                            "path": "MoonSight-v1.0.0-web-x86_64.zip",
                            "left_size_bytes": 123456,
                            "right_size_bytes": 123456,
                            "left_raw_sha256": "c" * 64,
                            "right_raw_sha256": "c" * 64,
                            "left_normalized_sha256": "c" * 64,
                            "right_normalized_sha256": "c" * 64,
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        metadata.write_text(
            json.dumps(
                {
                    "attempt_id": "rc-20260713T030000Z-111111111111",
                    "clean_tree": True,
                    "built_at_utc": "2026-07-13T03:00:00Z",
                    "build_host": "release-builder.example",
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
                    "validation_targets": {
                        "chromium": "138.0.7204.92",
                        "firefox": "140.0.4",
                        "webkitgtk": "2.48.3",
                    },
                }
            ),
            encoding="utf-8",
        )
        return benchmark, repro, metadata, output

    def test_generation_preserves_blocked_benchmark_status(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            benchmark, repro, metadata, output = self.write_inputs(
                root, benchmark_outcome="BLOCKED"
            )

            result = run_script(
                RC,
                "generate",
                "--candidate",
                SHA,
                "--benchmark",
                str(benchmark),
                "--reproducibility",
                str(repro),
                "--metadata",
                str(metadata),
                "--output",
                str(output),
            )

            self.assertNotEqual(result.returncode, 0)
            manifest = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(manifest["automated_checks"][0]["status"], "BLOCKED")
            self.assertNotIn("external_checks", manifest)

    def test_generation_is_schema_v2_candidate_identity_without_external_results(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            benchmark, repro, metadata, output = self.write_inputs(root)

            first = run_script(
                RC,
                "generate",
                "--candidate",
                SHA,
                "--benchmark",
                str(benchmark),
                "--reproducibility",
                str(repro),
                "--metadata",
                str(metadata),
                "--output",
                str(output),
            )
            self.assertEqual(first.returncode, 0, first.stderr)
            manifest = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(manifest["schema_version"], 2)
            self.assertEqual(manifest["attempt_id"], "rc-20260713T030000Z-111111111111")
            self.assertEqual(
                manifest["candidate"],
                {
                    "version": "v1.0.0",
                    "commit": SHA,
                    "architecture": "x86_64",
                    "clean_tree": True,
                    "built_at_utc": "2026-07-13T03:00:00Z",
                    "build_host": "release-builder.example",
                    "artifacts": [
                        {
                            "path": "MoonSight-v1.0.0-web-x86_64.zip",
                            "size_bytes": 123456,
                            "sha256": "c" * 64,
                        }
                    ],
                },
            )
            self.assertEqual(manifest["toolchains"]["moon"], "0.6.29+3f4c5d6")
            self.assertEqual(manifest["system"]["fedora"], "Fedora Linux 42")
            self.assertEqual(manifest["system"]["arch"], "Arch Linux 2026.07.01")
            self.assertEqual(
                manifest["validation_targets"]["chromium"], "138.0.7204.92"
            )
            self.assertEqual(manifest["reproducibility"]["input_sha256"], "b" * 64)
            self.assertEqual(manifest["reproducibility"]["report"]["path"], str(repro))
            self.assertRegex(
                manifest["reproducibility"]["report"]["sha256"],
                r"^[0-9a-f]{64}$",
            )
            self.assertEqual(len(manifest["required_evidence_ids"]), 13)
            self.assertNotIn("external_checks", manifest)
            self.assertNotIn("release_authorized", manifest)

    def test_generation_is_create_only(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            benchmark, repro, metadata, output = self.write_inputs(root)

            first = run_script(
                RC,
                "generate",
                "--candidate",
                SHA,
                "--benchmark",
                str(benchmark),
                "--reproducibility",
                str(repro),
                "--metadata",
                str(metadata),
                "--output",
                str(output),
            )
            second = run_script(
                RC,
                "generate",
                "--candidate",
                SHA,
                "--benchmark",
                str(benchmark),
                "--reproducibility",
                str(repro),
                "--metadata",
                str(metadata),
                "--output",
                str(output),
            )

            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertNotEqual(second.returncode, 0)
            self.assertIn("immutable RC manifest already exists", second.stderr)

    def test_generation_requires_complete_candidate_identity_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            benchmark, repro, metadata, output = self.write_inputs(root)
            data = json.loads(metadata.read_text(encoding="utf-8"))
            del data["attempt_id"]
            del data["validation_targets"]["firefox"]
            metadata.write_text(json.dumps(data), encoding="utf-8")

            result = run_script(
                RC,
                "generate",
                "--candidate",
                SHA,
                "--benchmark",
                str(benchmark),
                "--reproducibility",
                str(repro),
                "--metadata",
                str(metadata),
                "--output",
                str(output),
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("metadata.attempt_id must be a non-empty string", result.stderr)
            self.assertIn(
                "metadata.validation_targets.firefox must be a non-empty string",
                result.stderr,
            )

    def test_generation_rejects_missing_or_malformed_benchmark_input_digest(
        self,
    ) -> None:
        for digest in (None, "A" * 64):
            with self.subTest(digest=digest), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                benchmark, repro, metadata, output = self.write_inputs(root)
                benchmark_data = json.loads(benchmark.read_text(encoding="utf-8"))
                benchmark_data["input_sha256"] = digest
                benchmark.write_text(json.dumps(benchmark_data), encoding="utf-8")

                result = run_script(
                    RC,
                    "generate",
                    "--candidate",
                    SHA,
                    "--benchmark",
                    str(benchmark),
                    "--reproducibility",
                    str(repro),
                    "--metadata",
                    str(metadata),
                    "--output",
                    str(output),
                )

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    "benchmark.input_sha256 must be a 64-character lowercase "
                    "hexadecimal SHA-256 digest",
                    result.stderr,
                )
                self.assertFalse(output.exists())

    def test_release_evidence_template_names_all_public_and_raw_evidence_fields(
        self,
    ) -> None:
        template = json.loads(EVIDENCE_TEMPLATE.read_text(encoding="utf-8"))

        self.assertEqual(template["schema_version"], 1)
        self.assertIn(template["id"], ("W1-ubuntu-chromium", "REQUIRED_EVIDENCE_ID"))
        self.assertEqual(template["status"], "NOT_RUN")
        self.assertRegex(template["candidate_commit"], r"^[0-9a-f]{40}$")
        self.assertEqual(set(template["artifact"]), {"path", "sha256"})
        self.assertEqual(
            set(template["environment"]),
            {
                "os",
                "os_version",
                "kernel",
                "desktop_environment",
                "browser_or_webview",
                "browser_or_webview_version",
                "gpu",
                "driver",
            },
        )
        self.assertEqual(
            set(template["executed_steps"][0]),
            {"order", "action", "expected", "actual", "result"},
        )
        self.assertEqual(
            set(template["attachments"]),
            {"logs", "screenshots", "video"},
        )
        self.assertIn("save", template["redacted_inspection"])
        self.assertIn("localStorage", template["redacted_inspection"])
        self.assertRegex(template["public_evidence_sha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(template["raw_evidence_sha256"], r"^[0-9a-f]{64}$")
        self.assertTrue(template["redaction_statement"])

    def test_freeze_guard_rejects_tracked_diff_after_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp)
            subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=repo, check=True)
            tracked = repo / "tracked.txt"
            tracked.write_text("frozen\n", encoding="utf-8")
            subprocess.run(["git", "add", "tracked.txt"], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-qm", "candidate"], cwd=repo, check=True)
            candidate = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
            tracked.write_text("changed\n", encoding="utf-8")

            result = run_script(RC, "guard", "--candidate", candidate, "--repo", str(repo))

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("tracked worktree diff", result.stderr)


if __name__ == "__main__":
    unittest.main()
