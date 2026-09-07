"""Evaluate the real HM helper; probe installed OpenCode in disposable config dirs."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class Profiles(unittest.TestCase):
    def test_profiles(self):
        expression = '''let
          flake = builtins.getFlake "%s";
          lib = flake.inputs.nixpkgs.lib;
          module = import %s {
            inherit lib;
            config = { xdg.configHome = "/synthetic/config"; programs.opencode.package = "/synthetic/opencode"; };
            pkgs.writeShellScriptBin = name: text: { inherit name text; };
          };
        in module // { globalSettings = flake.nixosConfigurations.endeavour.config.home-manager.users.erik.programs.opencode.settings; }''' % (ROOT, ROOT / "modules/dev/_opencode-profiles.nix")
        result = subprocess.run(["nix", "eval", "--impure", "--json", "--expr", expression],
                                capture_output=True, text=True, check=True)
        module = json.loads(result.stdout)
        settings = module["globalSettings"]
        self.assertEqual(settings["model"], "litellm/glm-5.3-flash")
        self.assertEqual(settings["small_model"], "litellm/glm-5.3-flash")
        self.assertEqual(set(settings["provider"]), {"litellm", "work"})
        self.assertEqual(settings["enabled_providers"], ["litellm", "work"])
        self.assertEqual(len(settings["plugin"]), 4)
        self.assertEqual(settings["plugin"][3], "./plugins/gateway-headers.mjs")
        self.assertEqual(settings["plugin"][0], "./plugins/rtk.ts")
        self.assertTrue(settings["plugin"][1].endswith("/.opencode/plugins/ponytail.mjs"))
        self.assertEqual(settings["plugin"][2], "@tarquinen/opencode-dcp@3.1.15")
        self.assertTrue(all("model" not in agent for agent in settings["agent"].values()))
        self.assertEqual(settings["agent"]["architect"]["permission"], {"bash": "deny", "edit": "deny"})
        files = module["xdg"]["configFile"]
        self.assertEqual({item["name"] for item in module["home"]["packages"]},
                         {"opencode-home", "opencode-work", "opencode-home-omo", "opencode-work-omo"})
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            repo.mkdir()
            global_dir = root / "config/opencode"
            global_dir.mkdir(parents=True)
            providers = {provider: {"npm": "@ai-sdk/openai-compatible",
                         "options": {"baseURL": "http://127.0.0.1:9/v1", "apiKey": "synthetic"},
                         "models": {"glm-5.3-flash": {"name": "Synthetic"}}}
                         for provider in ["litellm", "work", "rogue"]}
            (global_dir / "opencode.json").write_text(json.dumps({"provider": providers}))
            (repo / "opencode.json").write_text(json.dumps({"model": "rogue/other", "enabled_providers": ["rogue"]}))
            for lane, provider in [("home", "litellm"), ("work", "work")]:
                model = provider + "/glm-5.3-flash"
                for suffix in ["", "-omo"]:
                    prefix = "opencode/profiles/" + lane + suffix + "/"
                    config = json.loads(files[prefix + "opencode.json"]["text"])
                    self.assertEqual(config["model"], model)
                    self.assertEqual(config["small_model"], model)
                    self.assertEqual(config["enabled_providers"], [provider])
                    self.assertNotIn("agent", config)
                    if suffix:
                        omo = json.loads(module["home"]["file"][".omo/omo.jsonc"]["text"])["profiles"][lane + suffix]["[opencode]"]
                        self.assertNotIn("general", omo["agents"])
                        self.assertNotIn("architect", omo["agents"])
                        for group in ["agents", "categories"]:
                            self.assertTrue(omo[group])
                            for definition in omo[group].values():
                                self.assertEqual(definition["model"], model)
                                self.assertEqual(definition["fallback_models"], [provider + "/deepseek-v4-flash"])
                        self.assertEqual(json.loads(files[prefix + "tui.json"]["text"])["plugin"], config["plugin"])
                    else:
                        self.assertNotIn("plugin", config)
                        self.assertEqual(config["default_agent"], "build")
                        profile = root / lane
                        profile.mkdir()
                        (profile / "opencode.json").write_text(json.dumps(config))
                        env = {key: value for key, value in os.environ.items() if not key.startswith("OPENCODE_CONFIG")}
                        env.update({"XDG_CONFIG_HOME": str(root / "config"), "XDG_DATA_HOME": str(root / "data"),
                                    "XDG_CACHE_HOME": str(root / "cache"), "XDG_STATE_HOME": str(root / "state"),
                                    "OPENCODE_CONFIG_DIR": str(profile), "OPENCODE_DISABLE_CLAUDE_CODE": "1"})
                        result = subprocess.run([shutil.which("opencode"), "debug", "config", "--pure"],
                                                cwd=repo, env=env, capture_output=True, text=True, check=True, timeout=30)
                        effective = json.loads(result.stdout)
                        self.assertEqual(effective["model"], model)
                        self.assertEqual(effective["enabled_providers"], [provider])
                        result = subprocess.run([shutil.which("opencode"), "models", "--pure"], cwd=repo,
                                                env=env, capture_output=True, text=True, check=True, timeout=30)
                        self.assertEqual(result.stdout.strip().splitlines(), [model])
            fake = root / "opencode"
            fake.write_text("#!/usr/bin/env python3\nimport os,sys,json\nprint(json.dumps({"
                            "'profile':os.environ['OPENCODE_CONFIG_DIR'],'omo_profile':os.environ.get('OMO_PROFILE'),"
                            "'stale':any(k in os.environ for k in ['OPENCODE_CONFIG','OPENCODE_CONFIG_CONTENT']),"
                            "'argv':sys.argv[1:]}))\n")
            fake.chmod(0o700)
            for launcher in module["home"]["packages"]:
                script = launcher["text"].replace("/synthetic/opencode/bin/opencode", str(fake))
                script = script.replace("/run/secrets/opencode/", str(root / "absent-secrets") + "/")
                env = {**os.environ, "OPENCODE_CONFIG": "stale", "OPENCODE_CONFIG_CONTENT": "stale", "OMO_PROFILE": "wrong"}
                result = subprocess.run(["bash", "-c", script, "launcher", "argument with spaces", "--flag"],
                                        env=env, capture_output=True, text=True, check=True)
                observed = json.loads(result.stdout)
                self.assertFalse(observed["stale"])
                self.assertEqual(observed["omo_profile"], launcher["name"].removeprefix("opencode-") if launcher["name"].endswith("-omo") else None)
                self.assertEqual(observed["argv"], ["argument with spaces", "--flag"])
                self.assertEqual(observed["profile"], "/synthetic/config/opencode/profiles/" + launcher["name"].removeprefix("opencode-"))


if __name__ == "__main__":
    unittest.main()
