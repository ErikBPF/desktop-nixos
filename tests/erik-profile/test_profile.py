"""Shared Erik profile keeps SSH and sops ownership on both hosts."""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
SHARED = {
    "nixvim",
    "codex",
    "opencode",
    "claude-code",
    "goose-cli",
    "hermes-agent",
    "pi",
    "pi-harness",
    "deepseek-harness",
    "herdr",
    "tuicr",
}


class ErikProfile(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = json.loads(subprocess.check_output([
            "nix", "eval", "--json", ".#nixosConfigurations", "--apply", '''hosts: {
              endeavour.sops = hosts.endeavour.config.home-manager.users.erik.sops;
              endeavour.files = builtins.attrNames hosts.endeavour.config.home-manager.users.erik.home.file;
              endeavour.packages = map (p: p.name or "") hosts.endeavour.config.home-manager.users.erik.home.packages;
              kepler.sops = hosts.kepler.config.home-manager.users.erik.sops;
              kepler.files = builtins.attrNames hosts.kepler.config.home-manager.users.erik.home.file;
              kepler.packages = map (p: p.name or "") hosts.kepler.config.home-manager.users.erik.home.packages;
            }'''], cwd=ROOT, text=True))

    def test_ssh_private_keys_are_sops_owned_on_both_hosts(self):
        for host in ("endeavour", "kepler"):
            sops = self.config[host]["sops"]
            for name in ("id_ed25519", "id_rsa"):
                secret = sops["secrets"][name]
                self.assertTrue(secret["path"].endswith("/.ssh/" + name))
                self.assertEqual(secret["mode"], "0400")
            self.assertTrue(sops["age"]["keyFile"].endswith("/.config/sops/age/keys.txt"))
            self.assertFalse(
                [path for path in self.config[host]["files"] if path.startswith(".ssh/id")],
                f"{host}: home.file must not compete with sops for SSH keys",
            )

    def test_shared_agent_tooling_is_present_on_both_hosts(self):
        for host in ("endeavour", "kepler"):
            names = set(self.config[host]["packages"])
            missing = {
                expected
                for expected in SHARED
                if not any(name == expected or name.startswith(expected + "-") for name in names)
            }
            self.assertFalse(missing, f"{host} missing {sorted(missing)}")


if __name__ == "__main__":
    unittest.main()
