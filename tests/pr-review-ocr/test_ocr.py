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
            15,
        )
        self.assertEqual(argv[0], "/bin/true")
        self.assertEqual(argv[argv.index("--timeout") + 1], "15")
        self.assertEqual(argv[argv.index("--model") + 1], "deepseek-v4.1-flash")
        self.assertEqual(argv[argv.index("--effort") + 1], "low")
        self.assertEqual(argv[argv.index("--audience") + 1], "agent")
        self.assertEqual(argv[argv.index("--output") + 1], "/bundle/ocr.json")

    def test_budget_is_the_pass_plus_slack_and_stays_inside_the_run_cap(self):
        cap = collect.OCR_RUN_BUDGET_SECONDS - collect.OCR_HEAD_OVERHEAD_SECONDS
        # A pass gets its own minutes plus two minutes of slack, so the CLI can
        # write its JSON before this wrapper kills it.
        for effort in ("low", "medium", "high"):
            self.assertEqual(
                collect.ocr_budget({"timeout_minutes": 15, "effort": effort}),
                15 * 60 + 120,
            )
        self.assertEqual(collect.ocr_budget({"timeout_minutes": 16}), cap)
        self.assertEqual(
            collect.ocr_budget({"timeout_minutes": 15}, remaining=700),
            700 - collect.OCR_HEAD_OVERHEAD_SECONDS,
        )

    def test_cli_minutes_stay_under_the_wrapper_kill(self):
        # OCR multiplies --timeout by the effort rounds, so the value handed
        # over is the allowance divided by them.
        budget = 15 * 60 + 120
        for effort, rounds in (("low", 1), ("medium", 2), ("high", 3)):
            minutes = collect.ocr_cli_minutes({"effort": effort}, budget)
            self.assertEqual(minutes, (budget - 120) // (60 * rounds))
            self.assertLessEqual(minutes * rounds * 60, budget - 120)
        # A clamp on the wrapper prunes the CLI budget too, not just the kill.
        clamped = 700 - collect.OCR_HEAD_OVERHEAD_SECONDS
        minutes = collect.ocr_cli_minutes({"effort": "low"}, clamped)
        self.assertEqual(minutes, (clamped - 120) // 60)
        self.assertLessEqual(minutes * 60, clamped - 120)
        self.assertGreaterEqual(collect.ocr_cli_minutes({"effort": "high"}, 200), 1)

    def test_run_budget_is_recorded_without_calling_ocr(self):
        from types import SimpleNamespace

        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory)
            args = SimpleNamespace(
                ocr={"enable": True, "repos": ["a/b"], "binary": "/bin/false"},
                ocr_deadline=0,
            )
            collect.ocr_candidates(args, "a/b", "b", "h", bundle, "unused")
            self.assertEqual(json.loads((bundle / "ocr.json").read_text())["status"], "skipped")

    def test_failure_is_recorded_and_not_raised(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "ocr.json"
            collect.ocr_execute({"binary": "/bin/false", "timeout_minutes": 1}, Path(directory), "b", "h", out, 60)
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
            collect.ocr_execute({"binary": str(fake), "timeout_minutes": 1}, Path(directory), "b", "h", out, 60)
            self.assertEqual(json.loads(out.read_text())["status"], "complete")


if __name__ == "__main__":
    unittest.main()
