from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERIFY = ROOT / "scripts" / "verify-package.sh"


def package(root: Path, manifest: dict[str, object]) -> None:
    (root / "index.html").write_text('<script src="app.js"></script>', encoding="utf-8")
    (root / "app.js").write_text("ok", encoding="utf-8")
    (root / "host_web.wasm").write_bytes(b"wasm")
    (root / "game.msb").write_bytes(b"MSB1fixture")
    (root / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")


class VerifyPackageTests(unittest.TestCase):
    def test_accepts_current_legacy_manifest_during_schema_transition(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            package(root, {"resources": {}, "audio": {}})
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
                },
            )
            result = subprocess.run([str(VERIFY), str(root)], text=True, capture_output=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("default_locale must appear in supported_locales", result.stderr)


if __name__ == "__main__":
    unittest.main()
