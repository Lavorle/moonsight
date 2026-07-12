from __future__ import annotations

import json
import hashlib
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERIFY = ROOT / "scripts" / "verify-package.sh"


def package(root: Path, manifest: dict[str, object] | None = None) -> dict[str, object]:
    (root / "index.html").write_text('<script src="app.js"></script>', encoding="utf-8")
    (root / "app.js").write_text("ok", encoding="utf-8")
    (root / "host_web.wasm").write_bytes(b"wasm")
    (root / "game.msb").write_bytes(b"MSB2" + struct.pack("<III", 2, 0, 0))
    if manifest is None:
        manifest = {
            "package_schema_version": 2,
            "default_locale": "en",
            "supported_locales": ["en"],
            "resources": {},
            "audio": {},
            "legacy_save_compatibility": {"schema_version": 1, "entries": []},
        }
    manifest["digests"] = {
        path.name: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in root.iterdir()
        if path.is_file()
    }
    (root / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    return manifest


class VerifyPackageTests(unittest.TestCase):
    def test_accepts_complete_schema_v2_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            package(root)
            result = subprocess.run([str(VERIFY), str(root)], text=True, capture_output=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_validates_locale_contract_when_package_schema_v2_is_present(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            package(
                root,
                {
                    "package_schema_version": 2,
                    "default_locale": "fr",
                    "supported_locales": ["en"],
                    "resources": {},
                    "audio": {},
                    "legacy_save_compatibility": {"schema_version": 1, "entries": []},
                },
            )
            result = subprocess.run([str(VERIFY), str(root)], text=True, capture_output=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("default_locale must appear in supported_locales", result.stderr)

    def test_rejects_digest_mismatch_and_undeclared_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = package(root)
            (root / "game.msb").write_bytes(b"MSB2corrupt")
            (root / "extra.bin").write_bytes(b"extra")
            (root / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            result = subprocess.run([str(VERIFY), str(root)], text=True, capture_output=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("digest mismatch for artifact: game.msb", result.stderr)
            self.assertIn("package artifact is undeclared in digests: extra.bin", result.stderr)


if __name__ == "__main__":
    unittest.main()
