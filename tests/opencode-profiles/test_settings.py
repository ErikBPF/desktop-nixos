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
        self.assertEqual(self.settings["mcp"]["donsetch"]["command"],
                         ["npx", "-y", "donsetch@4.7.4", "mcp", "--supervised"])
        # Search runs through donsetch; the built-in provider picker has no
        # donsetch backend and would otherwise win by being directly callable.
        self.assertIs(self.settings["websearch"], False)
        plugins = self.settings["plugins"]
        self.assertTrue(any("opencode-ponytail-v2-0.1.0" in p for p in plugins))
        self.assertFalse(any("dcp" in p or "context-fold" in p or "sidebar" in p for p in plugins))

    def test_secret_reads_hard_denied_even_after_agent_allow(self):
        rules = self.settings.get("permissions", [])
        policies = self.settings["experimental"]["policies"]
        paths = ["local.secrets.json", "nested/local.secret.json", ".env", ".env.local",
                 "nested/.env.production", "/home/erik/.ssh/id_ed25519",
                 ".ssh/id_rsa", "/home/erik/.config/sops/age/keys.txt", "private.age",
                 "/run/secrets/opencode/work_key"]
        for path in paths:
            with self.subTest(path=path):
                self.assertEqual(decision(rules, "read", path), "deny")
                # Agent permissions append after globals; policies must still block.
                self.assertEqual(decision(policies, "tool.use", "read:" + path, "allow"), "deny")
        self.assertEqual(decision(rules, "read", "modules/dev/opencode.nix"), "allow")

    def test_architect_shell_is_read_only(self):
        rules = self.settings["agents"]["architect"]["permissions"]
        for command in ["git commit -m x", "git push origin main", "rm -rf build",
                        "nixos-rebuild switch", "just deploy kepler",
                        "git log --oneline -p", "git log --oneline -U2",
                        "git diff --stat -p", "git diff --stat -U5",
                        "cat .env"]:
            with self.subTest(command=command):
                self.assertEqual(shell_decision(rules, command), "deny")
        for command in ["git status --short", "rg --files", "git log --oneline"]:
            with self.subTest(command=command):
                self.assertEqual(shell_decision(rules, command), "allow")
        self.assertEqual(decision(rules, "edit", "modules/dev/opencode.nix"), "deny")

    def test_shell_default_ask_and_preserved_denies(self):
        rules = self.settings.get("permissions", [])
        for command in ["cat README.md", "just home-switch", "just switch endeavour"]:
            with self.subTest(command=command):
                self.assertEqual(shell_decision(rules, command), "ask")
        for command in ["git status --short", "git diff --stat", "git branch --list", "rg --files"]:
            with self.subTest(command=command):
                self.assertEqual(shell_decision(rules, command), "allow")
        for command in ["cat .env", "git status; cat .env", "git status && cat .env",
                        "git diff --no-index /dev/null .env", "jq . .env", "fd -x cat .env",
                        "find . -exec cat .env +", "rg --pre cat pattern",
                        "nix eval --impure --expr 'builtins.readFile \"/etc/passwd\"'",
                        "git branch -D main", "git show HEAD:.env", "git show --stat HEAD:.env",
                        "rm -rf /", "rm -rf /etc", "docker volume rm db",
                        "docker rm -f db", "git push --force origin main",
                        "git push -f origin main", "git log --oneline -p",
                        "git log --oneline -U2", "git diff --stat --patch",
                        "git diff --stat -U5",
                        "nixos-rebuild switch --target-host kepler",
                        "ssh kepler nixos-rebuild switch", "ssh kepler docker compose up -d"]:
            with self.subTest(command=command):
                self.assertEqual(shell_decision(rules, command), "deny")
        self.assertEqual(decision(rules, "edit", "flake.lock"), "ask")
        for path in ["secrets/key.yaml", ".env", "nested/.env.local", "private.age", "encrypted.sops"]:
            self.assertEqual(decision(rules, "edit", path), "deny")


if __name__ == "__main__":
    unittest.main()
