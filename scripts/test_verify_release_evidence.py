from __future__ import annotations

import copy
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERIFIER = ROOT / "scripts" / "verify_release_evidence.py"
SHA = "1" * 40
DIGEST = "a" * 64


def valid_manifest() -> dict[str, object]:
    return {
        "schema_version": 1,
        "candidate": {
            "commit": SHA,
            "toolchains": {"moon": "1.2.3", "node": "22.0.0"},
            "artifacts": [
                {
                    "path": "dist/demo/game.msb",
                    "sha256": DIGEST,
                    "normalized_sha256": DIGEST,
                }
            ],
        },
        "generated_files": [
            {
                "path": "runtime/pkg.generated.mbti",
                "generator": "moon info",
                "owner": "runtime package API",
                "clean": True,
            }
        ],
        "automated_checks": [
            {
                "name": "moon test",
                "status": "PASS",
                "commit": SHA,
                "output": "evidence/moon-test.txt",
            }
        ],
        "external_checks": {
            name: {
                "status": "NOT_RUN",
                "commit": SHA,
                "artifacts": [
                    {"path": "dist/demo/game.msb", "sha256": DIGEST}
                ],
            }
            for name in ("W1", "D1", "C1")
        },
        "release_authorized": False,
    }


def run_verifier(manifest: dict[str, object], *args: str) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory() as temp_dir:
        path = Path(temp_dir) / "evidence.json"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        return subprocess.run(
            ["python3", str(VERIFIER), *args, str(path)],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )


class VerifyReleaseEvidenceTests(unittest.TestCase):
    def test_schema_accepts_truthful_not_run_external_checks(self) -> None:
        result = run_verifier(valid_manifest())

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("schema and exact-SHA evidence are consistent", result.stdout)

    def test_rejects_mixed_sha_automated_evidence(self) -> None:
        manifest = valid_manifest()
        manifest["automated_checks"][0]["commit"] = "2" * 40  # type: ignore[index]

        result = run_verifier(manifest)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("automated_checks[0].commit must equal candidate.commit", result.stderr)

    def test_rejects_invalid_artifact_checksum(self) -> None:
        manifest = valid_manifest()
        manifest["candidate"]["artifacts"][0]["sha256"] = "not-a-digest"  # type: ignore[index]

        result = run_verifier(manifest)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("candidate.artifacts[0].sha256", result.stderr)

    def test_rejects_external_artifact_digest_from_another_build(self) -> None:
        manifest = valid_manifest()
        manifest["external_checks"]["W1"]["artifacts"][0]["sha256"] = "b" * 64  # type: ignore[index]

        result = run_verifier(manifest)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "external_checks.W1.artifacts[0].sha256 must equal candidate artifact",
            result.stderr,
        )

    def test_release_ready_requires_real_environment_passes(self) -> None:
        result = run_verifier(valid_manifest(), "--require-release-ready")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("external_checks.W1.status must be PASS", result.stderr)
        self.assertIn("release_authorized must be true", result.stderr)

    def test_release_ready_accepts_one_exact_sha_and_authorization(self) -> None:
        manifest = copy.deepcopy(valid_manifest())
        for check in manifest["external_checks"].values():  # type: ignore[union-attr]
            check["status"] = "PASS"
        manifest["release_authorized"] = True

        result = run_verifier(manifest, "--require-release-ready")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("release-ready evidence is consistent", result.stdout)


if __name__ == "__main__":
    unittest.main()
