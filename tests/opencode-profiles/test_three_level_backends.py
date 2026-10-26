"""Three-level profiles generated for the ol/ow workspace backends."""
import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def rule(rules, action, resource, default="ask"):
    import fnmatch
    result = default
    for item in rules:
        if fnmatch.fnmatchcase(action, item["action"]) and fnmatch.fnmatchcase(resource, item["resource"]):
            result = item["effect"]
    return result


class ThreeLevelBackends(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        projection = '''home: {
          profiles = home.programs.opencode-backends.profiles;
          settings = home.programs.opencode.settings;
        }'''
        cls.home = json.loads(subprocess.check_output([
            "nix", "eval", "--json",
            ".#nixosConfigurations.endeavour.config.home-manager.users.erik",
            "--apply", projection,
        ], cwd=ROOT, text=True))
        cls.profiles = cls.home["profiles"]
        cls.settings = cls.home["settings"]

    def test_both_backends_use_the_three_level_hierarchy(self):
        self.assertEqual(sorted(self.profiles), ["dataplatform", "homelab"])
        for name, profile in self.profiles.items():
            with self.subTest(name):
                self.assertEqual(profile["default_agent"], "pilot-l1")
                self.assertEqual(sorted(profile["agents"]), ["pilot-l1", "pilot-l2", "pilot-l3"])

    def test_homelab_models_use_deepseek_with_layer_variants(self):
        profile = self.profiles["homelab"]
        self.assertEqual(profile["agents"]["pilot-l1"]["model"], "litellm/deepseek-v4.1-flash#max")
        self.assertEqual(profile["agents"]["pilot-l2"]["model"], "litellm/deepseek-v4.1-flash#high")
        self.assertEqual(profile["agents"]["pilot-l3"]["model"], "litellm/deepseek-v4.1-flash#high")
        self.assertEqual(profile["model"], "litellm/deepseek-v4.1-flash")
        self.assertEqual(profile["small_model"], "litellm/deepseek-v4.1-flash")

    def test_dataplatform_models_omit_unsupported_variants(self):
        profile = self.profiles["dataplatform"]
        for layer in ("pilot-l1", "pilot-l2", "pilot-l3"):
            self.assertEqual(profile["agents"][layer]["model"], "work/deepseek-v4.1-flash")

    def test_three_level_plugin_and_skills_are_added_once(self):
        for name, profile in self.profiles.items():
            with self.subTest(name):
                plugins = profile["plugins"]
                self.assertEqual(len(plugins), len(self.settings["plugins"]) + 1)
                self.assertTrue(any("three-level" in plugin for plugin in plugins))
                self.assertEqual(profile["skills"], ["/home/erik/.agents/skills"])

    def test_role_boundaries_and_auto_accept(self):
        for name, profile in self.profiles.items():
            with self.subTest(name):
                l1 = profile["agents"]["pilot-l1"]["permissions"]
                l2 = profile["agents"]["pilot-l2"]["permissions"]
                l3 = profile["agents"]["pilot-l3"]["permissions"]
                self.assertEqual(rule(l1, "edit", "src/main.py"), "deny")
                self.assertEqual(rule(l1, "edit", "docs/plan.md"), "ask")
                self.assertEqual(rule(l1, "shell", "git status"), "deny")
                self.assertEqual(rule(l1, "dispatch_slice", "*"), "allow")
                self.assertEqual(rule(l2, "subagent", "pilot-l3"), "allow")
                self.assertEqual(rule(l2, "subagent", "*"), "deny")
                self.assertEqual(rule(l3, "subagent", "*"), "deny")
                # L3 implements/edits; secret reads stay denied globally.
                self.assertFalse(any(item["action"] == "edit" for item in l3))
                self.assertEqual(rule(profile["permissions"], "read", "/run/secrets/opencode/work_key"), "deny")
                self.assertEqual(rule(profile["permissions"], "read",
                                 "/home/erik/.local/state/opencode-v2-backends/homelab/server-password"), "deny")
                self.assertEqual(rule(profile["permissions"], "edit",
                                 "/home/erik/.local/state/opencode-v2-backends/homelab/opencode.db"), "deny")

    def test_provider_policy_keeps_protected_denials(self):
        for name, profile in self.profiles.items():
            with self.subTest(name):
                policies = profile["experimental"]["policies"]
                providers = [item for item in policies if item["action"] == "provider.use"]
                self.assertEqual(rule(providers, "provider.use", "openai"), "allow")
                self.assertEqual(rule(providers, "provider.use", "*"), "deny")
                self.assertEqual(rule(policies, "tool.use", "read:/run/secrets/opencode/work_key"), "deny")

    def test_websearch_stays_disabled(self):
        for name, profile in self.profiles.items():
            with self.subTest(name):
                self.assertIs(profile["websearch"], False)


if __name__ == "__main__":
    unittest.main()
