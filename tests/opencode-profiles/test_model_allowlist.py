"""Exercise the managed model filter against OpenCode's real built-in catalog."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ModelAllowlist(unittest.TestCase):
    def test_managed_explicit_models_stay_within_approved_catalog(self):
        settings = json.loads(subprocess.check_output([
            "nix", "eval", "--json",
            ".#nixosConfigurations.endeavour.config.home-manager.users.erik.programs.opencode.settings",
        ], cwd=ROOT, text=True))
        approved = json.loads((ROOT / "modules/dev/pi-harness/src/approved-models.json").read_text())
        plugins = [plugin for plugin in settings["plugins"]
                   if isinstance(plugin, dict) and "model-allowlist" in plugin.get("package", "")]
        providers = settings["provider"]
        for provider in providers.values():
            provider["options"] = {"apiKey": "synthetic", "baseURL": "http://127.0.0.1:9/v1"}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "config/opencode"
            config.mkdir(parents=True)
            (config / "opencode.json").write_text(json.dumps({
                "update": "disable", "plugins": plugins, "provider": providers,
                "enabled_providers": settings["enabled_providers"],
            }))
            env = {"PATH": os.environ["PATH"], "HOME": directory,
                   "OPENCODE_DISABLE_MODELS_FETCH": "1", "OPENCODE_DISABLE_CLAUDE_CODE": "1"}
            env.update({f"XDG_{name}_HOME": str(root / name.lower())
                        for name in ["CONFIG", "DATA", "CACHE", "STATE"]})
            result = subprocess.check_output([
                os.environ.get("OPENCODE_TEST_BINARY", "opencode"), "models", "--standalone",
            ], cwd=directory, env=env, text=True, timeout=45)
        self.assertEqual(set(result.splitlines()), {
            f"{provider}/{model}"
            for provider in settings["enabled_providers"] for model in approved[provider]
        })

    def test_gateway_aliases_exist_in_both_clients(self):
        home = json.loads(subprocess.check_output([
            "nix", "eval", "--json",
            ".#nixosConfigurations.endeavour.config.home-manager.users.erik",
            "--apply", '''home: {
                opencode = home.programs.opencode.settings;
                pi = home.home.file.".pi/agent/models.json".text;
                settings = home.home.file.".pi/agent/settings.json".text;
            }''',
        ], cwd=ROOT, text=True))
        models = json.loads((ROOT / "modules/dev/pi-harness/src/approved-models.json").read_text())
        pi = json.loads(home["pi"])["providers"]
        settings = json.loads(home["settings"])
        for provider in ["litellm", "work"]:
            self.assertTrue(set(models[provider]) <= set(home["opencode"]["provider"][provider]["models"]))
            self.assertTrue(set(models[provider]) <= {model["id"] for model in pi[provider]["models"]})
        self.assertEqual(pi["opencode-go"]["apiKey"], "!cat /run/secrets/opencode/zen_key")
        self.assertIn("opencode-go/glm-5.3", settings["enabledModels"])
        self.assertIn("openai-codex/gpt-6-astra", settings["enabledModels"])
        self.assertIn("anthropic/claude-sonnet-5-5", settings["enabledModels"])
        self.assertNotIn("litellm/glm-5.3-flash", settings["enabledModels"])

    def test_astra_protocol_preserves_litellm_endpoint(self):
        settings = json.loads(subprocess.check_output([
            "nix", "eval", "--json",
            ".#nixosConfigurations.endeavour.config.home-manager.users.erik.programs.opencode.settings",
        ], cwd=ROOT, text=True))
        gateway = settings["provider"]["litellm"]
        gateway["options"] = {"apiKey": "synthetic", "baseURL": "http://127.0.0.1:9/v1"}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "config/opencode"
            config.mkdir(parents=True)
            (config / "opencode.json").write_text(json.dumps({
                "update": "disable", "provider": {"litellm": gateway},
                "providers": settings.get("providers", {}),
            }))
            env = {"PATH": os.environ["PATH"], "HOME": directory,
                   "OPENCODE_DISABLE_MODELS_FETCH": "1", "OPENCODE_DISABLE_CLAUDE_CODE": "1"}
            env.update({f"XDG_{name}_HOME": str(root / name.lower())
                        for name in ["CONFIG", "DATA", "CACHE", "STATE"]})
            sources = json.loads(subprocess.check_output([os.environ.get("OPENCODE_TEST_BINARY", "opencode"), "debug", "config", "--standalone"],
                                 cwd=directory, env=env, text=True, timeout=45))
        normalized = next(source["info"]["providers"]["litellm"] for source in sources
                          if source["type"] == "document")
        self.assertEqual(normalized.get("settings", {}).get("baseURL"), "http://127.0.0.1:9/v1")
        self.assertEqual(normalized["settings"]["apiKey"], "***")
        self.assertIn("deepseek-v4.1-flash", normalized["models"])
        self.assertEqual(normalized["models"]["codex-gpt-6.2-astra"]["package"],
                         "@opencode/ai/providers/openai-compatible/responses")

    def test_catalog_additions_stay_hidden(self):
        settings = json.loads(subprocess.check_output([
            "nix", "eval", "--json",
            ".#nixosConfigurations.endeavour.config.home-manager.users.erik.programs.opencode.settings",
        ], cwd=ROOT, text=True))
        plugins = [p for p in settings["plugins"]
                   if isinstance(p, dict) and "model-allowlist" in p.get("package", "")]
        approved = {"openai": ["gpt-5.6-sol"], "opencode-go": ["deepseek-v4.1-flash"]}
        if plugins:
            plugins[0]["options"] = {"models": approved}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "config/opencode"
            config.mkdir(parents=True)
            (config / "opencode.json").write_text(json.dumps({
                "update": "disable", "plugins": plugins,
                "providers": {provider: {"settings": {"apiKey": "synthetic"}}
                              for provider in approved},
                "policies": [{"action": "provider.use", "resource": "*", "effect": "deny"},
                             *[{"action": "provider.use", "resource": provider, "effect": "allow"}
                               for provider in approved]],
            }))
            env = {"PATH": os.environ["PATH"], "HOME": directory,
                   "OPENCODE_DISABLE_MODELS_FETCH": "1", "OPENCODE_DISABLE_CLAUDE_CODE": "1"}
            env.update({f"XDG_{name}_HOME": str(root / name.lower())
                        for name in ["CONFIG", "DATA", "CACHE", "STATE"]})
            result = subprocess.check_output([os.environ.get("OPENCODE_TEST_BINARY", "opencode"), "models", "--standalone"],
                                             cwd=directory, env=env, text=True, timeout=45)
        self.assertEqual(set(result.splitlines()),
                         {f"{provider}/{model}" for provider, models in approved.items() for model in models})


if __name__ == "__main__":
    unittest.main()
