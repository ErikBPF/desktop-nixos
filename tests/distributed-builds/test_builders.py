import json
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ORION = "ssh-ng://erik@orion-builder:2222"
APOLLO = "ssh-ng://erik@apollo-builder:2222"


def recipe_pool(target, env=None):
    result = subprocess.run(
        ["just", "--no-dotenv", "_builders", target],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
        env=os.environ | (env or {}),
    )
    return [spec.strip().split() for spec in result.stdout.strip().split(";")]


def nix_eval(attribute):
    result = subprocess.run(
        ["nix", "eval", "--json", f"{ROOT}#{attribute}"],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def test_endeavour_uses_only_orion():
    machines = nix_eval("nixosConfigurations.endeavour.config.nix.buildMachines")
    assert [machine["hostName"] for machine in machines] == ["orion-builder"]


def test_kepler_never_uses_itself_as_a_remote_builder():
    machines = nix_eval("nixosConfigurations.kepler.config.nix.buildMachines")
    assert [machine["hostName"] for machine in machines] == ["orion-builder"]


def test_kepler_retains_existing_ssh_authorization():
    keys = nix_eval(
        "nixosConfigurations.kepler.config.users.users.erik.openssh.authorizedKeys.keys"
    )
    assert any(key.endswith("nix-builder@laptop") for key in keys)


def test_recipe_pool_is_orion_plus_apollo_and_excludes_kepler():
    for target in ("apollo", "kepler", "endeavour", "pathfinder", "discovery", "all"):
        specs = recipe_pool(target)
        assert [spec[0] for spec in specs] == [ORION, APOLLO], target
        orion, apollo = specs
        assert orion[1] == "i686-linux,x86_64-linux,aarch64-linux"
        assert orion[3:5] == ["8", "2"]
        assert "kvm" not in orion[5].split(",")
        assert apollo[1] == "i686-linux,x86_64-linux"
        assert apollo[3:5] == ["6", "1"]
        assert set(apollo[5].split(",")) == {"big-parallel", "benchmark", "kvm", "nixos-test"}
        assert all(spec[2] == "/home/erik/.ssh/id_ed25519" for spec in specs)
        assert not any("kepler-builder" in spec[0] for spec in specs)


def test_orion_target_stays_orion_only():
    # Orion builds through itself on recovery paths; a second builder would
    # hide a broken Orion store or daemon.
    specs = recipe_pool("orion")
    assert [spec[0] for spec in specs] == [ORION]


def test_empty_apollo_builder_falls_back_to_orion_only():
    specs = recipe_pool("apollo", {"apollo_builder": ""})
    assert [spec[0] for spec in specs] == [ORION]


def test_builder_aliases_require_pinned_noninteractive_host_authentication():
    extra_config = nix_eval("nixosConfigurations.endeavour.config.programs.ssh.extraConfig")
    builder_config = extra_config.split("\nHost *\n", 1)[0]
    for host in ("orion", "apollo"):
        assert f"Match originalhost {host}-builder localnetwork 192.168.10.0/24" in extra_config
        assert f"Host {host}-builder\n" in extra_config
    assert extra_config.count("StrictHostKeyChecking yes") >= 2
    assert extra_config.count("BatchMode yes") >= 2
    assert extra_config.count("HostKeyAlias [") >= 2
    assert "StrictHostKeyChecking accept-new" not in builder_config
