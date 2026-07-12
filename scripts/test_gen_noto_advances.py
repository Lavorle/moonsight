from __future__ import annotations

import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scripts" / "gen_noto_advances.mjs"
OUTPUT = ROOT / "render" / "noto_advances.mbt"


class NotoAdvancesGeneratorTests(unittest.TestCase):
    def test_regeneration_is_clean_and_has_one_final_newline(self) -> None:
        original = OUTPUT.read_bytes()
        try:
            result = subprocess.run(
                ["node", str(GENERATOR)],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            generated = OUTPUT.read_bytes()
        finally:
            OUTPUT.write_bytes(original)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(generated, original)
        self.assertTrue(generated.endswith(b"}\n"))
        self.assertFalse(generated.endswith(b"}\n\n"))


if __name__ == "__main__":
    unittest.main()
