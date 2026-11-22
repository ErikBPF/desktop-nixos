"""Evaluate managed V2 settings without resolving credential substitutions."""
import fnmatch
import json
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


def matches(value, pattern):
    if fnmatch.fnmatchcase(value, pattern):
        return True
    # A shell pattern ending in " *" also matches the command without arguments.
    return pattern.endswith(" *") and value == pattern[:-2]


def decision(rules, action, resource, default="ask"):
    result = default
    for rule in rules:
        if matches(action, rule["action"]) and matches(resource, rule["resource"]):
            result = rule["effect"]
    return result


def shell_decision(rules, command):
    # The shell scanner evaluates every subcommand separately.
    parts = re.split(r"\s*(?:;|&&|\|\||\|)\s*", command)
    effects = [decision(rules, "shell", part) for part in parts]
    if "deny" in effects:
        return "deny"
    return "ask" if "ask" in effects else "allow"


class ManagedSettings(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        projection = '''home: {
          settings = home.programs.opencode.settings;
          cli = home.xdg.configFile."opencode/cli.json".text or "{}";
          legacyTui = builtins.hasAttr "opencode/tui.json" home.xdg.configFile;
          rustClient = home.programs.opencode-tui.enable or false;
        }'''
        cls.home = json.loads(subprocess.check_output([
            "nix", "eval", "--json",
            ".#nixosConfigurations.endeavour.config.home-manager.users.erik",
            "--apply", projection,
        ], cwd=ROOT, text=True))
        cls.settings = cls.home["settings"]

    def test_native_global_cli(self):
        cli = json.loads(self.home["cli"])
        self.assertEqual(cli.get("theme"), {"name": "tokyonight", "mode": "system"})
        self.assertEqual(cli.get("session", {}).get("permissions"), "autoaccept")
        self.assertEqual(cli.get("session", {}).get("sidebar"), "auto")
        self.assertEqual(cli.get("tabs", {}).get("mode"), "off")
        self.assertNotIn("keybinds", cli)
        self.assertFalse(self.home["legacyTui"])
        self.assertFalse(self.home["rustClient"])

    def test_supported_compaction_and_managed_update(self):
        self.assertEqual(self.settings.get("update"), "disable")
        self.assertEqual(self.settings["compaction"], {"auto": True, "keep": {"tokens": 15000}})

    def test_pinned_integrations_and_optional_plugins_absent(self):
        cmd = self.settings["mcp"]["donsetch"]["command"]
        self.assertTrue(cmd[0].startswith("/nix/store/") and cmd[0].endswith("/bin/donsetch"), cmd[0])
        self.assertEqual(cmd[1:], ["mcp", "--supervised"])
        self.assertIs(self.settings["mcp"]["donsetch"]["enabled"], True)
        # Search runs through donsetch; the built-in provider picker has no
        # donsetch backend and would otherwise win by being directly callable.
        self.assertIs(self.settings["websearch"], False)
        plugins = self.settings["plugins"]
        self.assertTrue(any("opencode-ponytail-v2-0.1.0" in p for p in plugins))
        self.assertFalse(any("dcp" in p or "context-fold" in p or "sidebar" in p for p in plugins))

    def test_secret_reads_use_invoking_user_authority(self):
        rules = self.settings.get("permissions", [])
        policies = self.settings["experimental"]["policies"]
        paths = ["local.secrets.json", "nested/local.secret.json", ".env", ".env.local",
                 "nested/.env.production", "/home/erik/.ssh/id_ed25519",
                 ".ssh/id_rsa", "/home/erik/.config/sops/age/keys.txt", "private.age",
                 "/run/secrets/opencode/work_key"]
        for path in paths:
            with self.subTest(path=path):
                self.assertEqual(decision(rules, "read", path), "allow")
                # No hard policy may override the requested read authority.
                self.assertEqual(decision(policies, "tool.use", "read:" + path, "allow"), "allow")
        self.assertEqual(decision(rules, "read", "modules/dev/opencode.nix"), "allow")

    def test_architect_inherits_global_permissions(self):
        architect = self.settings["agents"]["architect"]
        # Architect keeps its role but no longer narrows the global policy.
        self.assertNotIn("permissions", architect)
        rules = self.settings.get("permissions", [])
        for command in ["git status --short", "git commit -m x", "git push origin main"]:
            with self.subTest(command=command):
                self.assertEqual(shell_decision(rules, command), "allow")
        for command in [f"cat .env", f"git show HEAD:.env"]:
            with self.subTest(command=command):
                self.assertEqual(shell_decision(rules, command), "allow")
        self.assertEqual(decision(rules, "edit", "modules/dev/opencode.nix"), "allow")
        self.assertEqual(decision(rules, "edit", f".env"), "allow")

    def test_shell_and_edits_use_invoking_user_authority(self):
        rules = self.settings.get("permissions", [])
        for command in ["cat README.md", "just switch endeavour", "gh pr create --fill",
                        "git push --force origin main", "git push -f origin main",
                        "git log --oneline -p", "git diff --stat -U5",
                        "python3 -c 'import os; print(os.environ)'",
                        "kubectl get pod x -o jsonpath='{.spec.containers[0].env[*]}'",
                        "find . -maxdepth 1 -name '*.md' -exec wc -l {} +",
                        "nix eval --impure --expr '1 + 1'"]:
            with self.subTest(command=command):
                self.assertEqual(shell_decision(rules, command), "allow")
        # Ordinary inspection and previously denied commands share the same authority.
        for command in ["git show HEAD:modules/dev/opencode.nix", "ls .agents",
                        "ls ~/.agents/skills"]:
            with self.subTest(command=command):
                self.assertEqual(shell_decision(rules, command), "allow")
        for command in [
                        "cat .env",
                        "cat .env.example .env",
                        "git diff --no-index /dev/null .env",
                        "jq . .env",
                        "rg -n \"secrets/\" README.md",
                        "cat \"secrets/prod.yaml\"",
                        "cat 'secrets/key'",
                        "python3 -c \"open('.env').read()\"",
                        "python3 -c 'open(\".env\").read()'",
                        "node -e \"console.log(require('fs').readFileSync('.env','utf8'))\"",
                        "python3 -c \"open('secrets/k').read()\"",
                        "fd -x cat .env",
                        "find . -exec cat .env +",
                        "git branch -D main",
                        "git show HEAD:.env",
                        "git show --stat HEAD:.env",
                        "rm -rf /",
                        "rm -rf /etc",
                        "docker volume rm db",
                        "docker rm -f db",
                        "nixos-rebuild switch --target-host kepler",
                        "ssh kepler nixos-rebuild switch",
                        "ssh kepler docker compose up -d",
        ]:
            with self.subTest(command=command):
                self.assertEqual(shell_decision(rules, command), "allow")
        self.assertEqual(decision(rules, "edit", "flake.lock"), "allow")
        for path in ["secrets/key.yaml", f".env", f"nested/.env.local", "private.age", "encrypted.sops"]:
            self.assertEqual(decision(rules, "edit", path), "allow")

if __name__ == "__main__":
    unittest.main()
