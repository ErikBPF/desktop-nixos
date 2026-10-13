"""Project overrides must not bypass the managed OpenCode integrations."""
import json
import fnmatch
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class ProjectConfiguration(unittest.TestCase):
    def setUp(self):
        self.config = json.loads((ROOT / "opencode.json").read_text())

    def test_inherit_packaged_mcp_and_native_filesystem_tools(self):
        self.assertNotIn("nix", self.config.get("mcp", {}))
        self.assertNotIn("filesystem", self.config.get("mcp", {}))

    def test_unlisted_shell_and_deployment_commands_require_approval(self):
        rules = self.config["permission"]["bash"]
        self.assertEqual(rules["*"], "ask")
        for broad in ("just *", "nix build *", "nix flake *"):
            self.assertNotEqual(rules.get(broad), "allow")
        for inspection in ("git status --short", "git diff --stat"):
            self.assertTrue(any(fnmatch.fnmatchcase(inspection, pattern) and effect == "allow"
                                for pattern, effect in rules.items()))

    def test_inspection_allowances_cannot_include_secret_reads_or_compounds(self):
        rules = self.config["permission"]["bash"]
        for command in ("git status; cat .env", "rtk git status && cat .env",
                        "git diff --no-index /dev/null .env", "rtk git diff -- .env"):
            effect = "ask"
            for pattern, candidate in rules.items():
                if fnmatch.fnmatchcase(command, pattern):
                    effect = candidate
            self.assertEqual(effect, "ask", command)

    def test_existing_destructive_denials_remain(self):
        rules = self.config["permission"]["bash"]
        for pattern in ("rm -rf /*", "rm -rf ~*", "docker volume rm *",
                        "docker rm -f *", "*nixos-rebuild*--target-host*"):
            self.assertEqual(rules[pattern], "deny")

    def test_optional_experiment_fragments_are_pinned_and_private(self):
        directory = ROOT / "modules/dev/opencode-experiments"
        fold = json.loads((directory / "context-fold.json").read_text())["plugins"][0]
        self.assertEqual(fold["package"],
                         "github:GitMacke/opencode-context-fold#"
                         "a8347566f996ed51d9d6d06f9f56ae88b6d1f5f4")
        self.assertFalse(fold["options"]["debug"])
        usage = json.loads((directory / "usage-sidebar.json").read_text())["plugins"][0]
        self.assertEqual(usage["package"], "opencode-plugin-usage@2.0.4")
        self.assertEqual(usage["options"]["default"], "none")


if __name__ == "__main__":
    unittest.main()
