"""Project overrides must not bypass the managed OpenCode integrations."""
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class ProjectConfiguration(unittest.TestCase):
    def setUp(self):
        self.config = json.loads((ROOT / "opencode.json").read_text())

    def test_inherit_packaged_mcp_and_native_filesystem_tools(self):
        self.assertNotIn("nix", self.config.get("mcp", {}))
        self.assertNotIn("filesystem", self.config.get("mcp", {}))

    def test_coding_tools_use_invoking_user_authority(self):
        permissions = self.config["permission"]
        for action in ("read", "edit", "bash", "external_directory"):
            self.assertEqual(permissions[action], {"*": "allow"})

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
