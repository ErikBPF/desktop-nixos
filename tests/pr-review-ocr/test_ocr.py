import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/pr-review"))

import collect  # noqa: E402


class OcrCandidateTest(unittest.TestCase):
    def test_gating_requires_enable_and_repo(self):
        cfg = {"enable": True, "repos": ["ErikBPF/desktop-nixos"]}
        self.assertIsNotNone(collect.ocr_settings({"ocr": cfg}, "ErikBPF/desktop-nixos"))
        self.assertIsNone(collect.ocr_settings({"ocr": cfg}, "ErikBPF/other"))
        self.assertIsNone(collect.ocr_settings({"ocr": {**cfg, "enable": False}}, "ErikBPF/desktop-nixos"))
        self.assertIsNone(collect.ocr_settings({"ocr": {**cfg, "repos": []}}, "ErikBPF/desktop-nixos"))
        self.assertIsNone(collect.ocr_settings(None, "ErikBPF/desktop-nixos"))

    def test_invocation_pins_model_effort_and_json(self):
        argv = collect.ocr_invocation(
            {"binary": "/bin/true", "model": "deepseek-v4.1-flash", "effort": "low", "timeout_minutes": 5},
            Path("/worktree"),
            "base-sha",
            "head-sha",
            Path("/bundle/ocr.json"),
        )
        self.assertEqual(argv[0], "/bin/true")
        self.assertEqual(argv[argv.index("--model") + 1], "deepseek-v4.1-flash")
        self.assertEqual(argv[argv.index("--effort") + 1], "low")
        self.assertEqual(argv[argv.index("--audience") + 1], "agent")
        self.assertEqual(argv[argv.index("--output") + 1], "/bundle/ocr.json")

    def test_failure_is_recorded_and_not_raised(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "ocr.json"
            collect.ocr_execute({"binary": "/bin/false", "timeout_minutes": 1}, Path(directory), "b", "h", out)
            self.assertEqual(json.loads(out.read_text())["status"], "error")

    def test_success_output_is_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            fake = Path(directory) / "fake-ocr"
            fake.write_text(
                "#!/bin/sh\nout=''\nwhile [ $# -gt 0 ]; do [ \"$1\" = --output ] && out=\"$2\"; shift; done\n"
                "printf '%s' '{\"status\":\"complete\",\"comments\":[]}' > \"$out\"\n"
            )
            fake.chmod(0o755)
            out = Path(directory) / "ocr.json"
            collect.ocr_execute({"binary": str(fake), "timeout_minutes": 1}, Path(directory), "b", "h", out)
            self.assertEqual(json.loads(out.read_text())["status"], "complete")


if __name__ == "__main__":
    unittest.main()
