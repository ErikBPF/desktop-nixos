#!/usr/bin/env python3
"""Capture build, deploy and read-only state wiring argv; never runs Nix or SSH."""

import json
import os
from pathlib import Path
import subprocess


def main():
    root = Path(__file__).resolve().parents[1]
    hosts = json.loads((root / "fleet.json").read_text())["hosts"]
    orion = "ssh-ng://erik@orion-builder:2222"
    apollo = "ssh-ng://erik@apollo-builder:2222"
    overlay = hosts["orion"]["tailscaleIp"]
    overlay_overrides = ["--set", "orion_builder",
                 f"ssh-ng://erik@{overlay}:2222 x86_64-linux /home/erik/.ssh/id_ed25519 16 2 big-parallel,benchmark,nixos-test",
                 "--set", "apollo_builder", ""]
    cases = (
        ("discovery", overlay_overrides,
         [f"ssh-ng://erik@{overlay}:2222"]),
        ("discovery", [], [orion, apollo]),
        ("orion", [], [apollo]),
        ("apollo", [], [orion]),
    )
    for target, overrides, expected in cases:
        result = subprocess.run(
            ["bash", "--noprofile", "--norc", "-c",
             'nix() { printf \'%s\\n\' "$@"; }\nexport -f nix\n'
             'exec just --no-dotenv --shell bash --shell-arg -c "$@"',
             "hermes-orion-build", *overrides, "build", target],
            cwd=root, env={"PATH": os.environ["PATH"], "HOME": os.environ["HOME"]},
            check=True, capture_output=True, text=True, timeout=30,
        )
        argv = result.stdout.splitlines()
        builders = argv[argv.index("--builders") + 1].strip(" ;")
        actual = [builder.split()[0] for builder in builders.split(";")]
        assert actual == expected, f"{target}: expected {expected}, got {actual}"
        assert argv[0] == "build" and "--no-link" in argv
        assert argv[argv.index("--max-jobs") + 1] == "1"
        assert "--builders-use-substitutes" in argv
        assert f".#nixosConfigurations.{target}.config.system.build.toplevel" in argv
    print("PASS: Orion override, Orion/Apollo defaults and bounded fallback (4 cases)")
    result = subprocess.run(
        ["bash", "--noprofile", "--norc", "-c",
         'ssh() { printf \'%s\\n\' "$@"; }\nexport -f ssh\n'
         'exec just --no-dotenv --shell bash --shell-arg -c "$@"',
         "hermes-agents-state", "--set", "ip_discovery",
         hosts["discovery"]["tailscaleIp"], "hermes-agents-state"],
        cwd=root, env={"PATH": os.environ["PATH"], "HOME": os.environ["HOME"]},
        capture_output=True, text=True, timeout=30,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        "-p", "2222", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15",
        f"erik@{hosts['discovery']['tailscaleIp']}",
        "systemctl show docker-hermes-argus.service docker-hermes-agent.service "
        "hermes-argus-healthcheck.timer hermes-agent-healthcheck.timer "
        "--property=Id --property=LoadState --property=ActiveState "
        "--property=SubState --no-pager",
    ], result.stdout
    print("PASS: fixed four-unit read-only state argv (1 case; 5 cases total)")
    for recipe in ("deploy-rs", "deploy-rs-preview"):
        result = subprocess.run(
            ["bash", "--noprofile", "--norc", "-c",
             'nix() { printf \'%s\\n\' "$@"; }\nexport -f nix\n'
             'exec just --no-dotenv --shell bash --shell-arg -c "$@"',
              "hermes-orion-deploy", *overlay_overrides, recipe, "discovery",
             hosts["discovery"]["tailscaleIp"]],
            cwd=root, env={"PATH": os.environ["PATH"], "HOME": os.environ["HOME"]},
            check=True, capture_output=True, text=True, timeout=30,
        )
        argv = result.stdout.splitlines()
        builders_index = argv.index("builders")
        assert argv[builders_index - 1] == "--option"
        builders = argv[builders_index + 1].strip(" ;")
        actual = [builder.split()[0] for builder in builders.split(";")]
        expected = [f"ssh-ng://erik@{overlay}:2222"]
        assert actual == expected, f"{recipe}: expected {expected}, got {actual}"
        assert argv[:2] == ["run", "--builders"]
        assert argv[2].strip(" ;") == builders
        assert argv[argv.index(".#deploy-rs") + 1] == "--"
        assert argv[argv.index("--hostname") + 1] == hosts["discovery"]["tailscaleIp"]
        assert ("--dry-activate" in argv) == (recipe == "deploy-rs-preview")
        assert argv[argv.index("--max-jobs") + 1] == "1"
        assert "--skip-checks" in argv and ".#discovery" in argv
        assert argv[argv.index("builders-use-substitutes") + 1] == "true"
    print("PASS: deploy and preview preserve Orion overrides (2 cases; 7 cases total)")


if __name__ == "__main__":
    main()
