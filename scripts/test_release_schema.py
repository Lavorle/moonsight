from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))

from release_schema import (
    REQUIRED_EVIDENCE_IDS,
    read_object,
    sha256_file,
    validate_sha256,
)


class ReleaseSchemaTests(unittest.TestCase):
    def test_required_matrix_is_closed_and_unique(self) -> None:
        self.assertEqual(len(REQUIRED_EVIDENCE_IDS), 13)
        self.assertEqual(len(set(REQUIRED_EVIDENCE_IDS)), 13)
        self.assertEqual(REQUIRED_EVIDENCE_IDS[0], "W1-ubuntu-chromium")
        self.assertEqual(REQUIRED_EVIDENCE_IDS[-1], "C1-desktop")

    def test_sha256_file_hashes_exact_file_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "artifact.bin"
            path.write_bytes(b"MoonSight\x00Formal 1.0\n")

            self.assertEqual(
                sha256_file(path),
                "51880f433184fdd1e210d649771e8090812ff27f3c1ac391df6d8e22b04eaf81",
            )

    def test_read_object_returns_json_object(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "record.json"
            path.write_text('{"schema_version": 1}', encoding="utf-8")

            self.assertEqual(read_object(path, "evidence record"), {"schema_version": 1})

    def test_read_object_rejects_non_object_json(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "candidate.json"
            path.write_text("[]", encoding="utf-8")

            with self.assertRaisesRegex(
                ValueError, "^candidate manifest must be an object$"
            ):
                read_object(path, "candidate manifest")

    def test_read_object_wraps_file_encoding_and_json_errors(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            invalid_utf8 = root / "invalid-utf8.json"
            invalid_utf8.write_bytes(b"\xff")
            invalid_json = root / "invalid-json.json"
            invalid_json.write_text("{", encoding="utf-8")
            paths = (root / "missing.json", invalid_utf8, invalid_json)

            for path in paths:
                with self.subTest(path=path.name):
                    with self.assertRaisesRegex(
                        ValueError, "^cannot read evidence record:"
                    ):
                        read_object(path, "evidence record")

    def test_validate_sha256_accepts_exact_lowercase_digest(self) -> None:
        errors: list[str] = []
        digest = "0123456789abcdef" * 4

        self.assertEqual(validate_sha256(digest, "artifact.sha256", errors), digest)
        self.assertEqual(errors, [])

    def test_validate_sha256_rejects_noncanonical_values(self) -> None:
        invalid_values = (
            None,
            123,
            "a" * 63,
            "a" * 65,
            "A" * 64,
            "g" * 64,
            f"{'a' * 64}\n",
        )

        for value in invalid_values:
            with self.subTest(value=value):
                errors: list[str] = []
                self.assertEqual(validate_sha256(value, "artifact.sha256", errors), "")
                self.assertEqual(
                    errors,
                    [
                        "artifact.sha256 must be a 64-character lowercase "
                        "hexadecimal SHA-256 digest"
                    ],
                )


if __name__ == "__main__":
    unittest.main()
