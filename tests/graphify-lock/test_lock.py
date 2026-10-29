"""Graphify wheel locking: exact public artifacts and offline build inputs."""

import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/update-graphify-lock.py"
LOCK = ROOT / "modules/dev/graphify-lock.json"


def report():
    return {"version": "1", "install": [{
        "metadata": {"name": "graphifyy", "version": "0.9.53"},
        "download_info": {
            "url": "https://files.pythonhosted.org/packages/example/graphifyy-0.9.53-py3-none-any.whl",
            "archive_info": {"hashes": {"sha256": "ab" * 32}},
        },
        "is_yanked": False,
    }]}


class WheelLockTests(unittest.TestCase):
    def test_dependency_prs_keep_read_only_checks_on_non_main_bases(self):
        for name in ("check.yml", "security.yml"):
            source = (ROOT / ".github/workflows" / name).read_text()
            with self.subTest(workflow=name):
                self.assertIn("  pull_request: {}\n", source)
                self.assertIn("  push:\n    branches: [main]\n", source)
                self.assertIn("permissions:\n  contents: read\n", source)

    def test_secret_scan_has_explicit_read_capability_without_comment_writes(self):
        source = (ROOT / ".github/workflows/security.yml").read_text()
        self.assertIn("  pull-requests: read\n", source)
        self.assertIn('GITLEAKS_ENABLE_COMMENTS: "false"', source)
        self.assertNotIn(": write", source)

    def generator(self):
        self.assertTrue(SCRIPT.is_file(), "The wheel lock needs an explicit update command")
        spec = importlib.util.spec_from_file_location("graphify_lock", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_exact_public_artifact_and_digest_survive_conversion(self):
        lock = self.generator().lock_from_report(report(), "0.9.53")
        self.assertEqual(lock["version"], "0.9.53")
        self.assertEqual(lock["pythonVersion"], "3.14")
        self.assertEqual(lock["system"], "x86_64-linux")
        wheel = lock["wheels"][0]
        self.assertEqual(wheel["url"], report()["install"][0]["download_info"]["url"])
        self.assertEqual(wheel["sha256"], "ab" * 32)
        self.assertEqual(wheel["filename"], "graphifyy-0.9.53-py3-none-any.whl")

    def test_rejects_untrusted_or_incomplete_resolution(self):
        module = self.generator()
        cases = []
        for url in ["http://files.pythonhosted.org/a.whl", "https://example.org/a.whl",
                    "https://user:password@files.pythonhosted.org/a.whl",
                    "https://files.pythonhosted.org/a.tar.gz",
                    "https://files.pythonhosted.org/a.whl?token=private"]:
            candidate = report()
            candidate["install"][0]["download_info"]["url"] = url
            cases.append(candidate)
        for digest in ["", "x" * 64, "ab" * 31]:
            candidate = report()
            candidate["install"][0]["download_info"]["archive_info"]["hashes"]["sha256"] = digest
            cases.append(candidate)
        candidate = report()
        candidate["version"] = "2"
        cases.append(candidate)
        candidate = report()
        candidate["install"][0]["is_yanked"] = True
        cases.append(candidate)
        candidate = report()
        candidate["install"].append(copy.deepcopy(candidate["install"][0]))
        cases.append(candidate)
        candidate = report()
        candidate["install"] = []
        cases.append(candidate)
        for candidate in cases:
            with self.subTest(candidate=candidate):
                with self.assertRaises(ValueError):
                    module.lock_from_report(candidate, "0.9.53")
        with self.assertRaises(ValueError):
            module.lock_from_report(report(), "0.9.54")

    def test_checked_in_closure_is_complete_and_build_does_not_resolve_from_index(self):
        self.assertTrue(LOCK.is_file(), "All transitive wheels must be locked before building")
        lock = json.loads(LOCK.read_text())
        self.assertGreater(len(lock["wheels"]), 1, "Transitive artifacts must be locked too")
        filenames = [wheel["filename"] for wheel in lock["wheels"]]
        self.assertEqual(len(filenames), len(set(filenames)))
        self.assertTrue(any(name.startswith("graphifyy-" + lock["version"] + "-") for name in filenames))
        source = (ROOT / "modules/dev/opencode.nix").read_text()
        self.assertIn("./graphify-lock.json", source)
        self.assertIn("pkgs.fetchurl", source)
        self.assertNotIn("pip\" download", source)
        self.assertNotIn("uv venv --seed", source)
        self.assertIn("--no-index", source)


if __name__ == "__main__":
    unittest.main()
