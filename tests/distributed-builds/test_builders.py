import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def nix_eval(attribute):
    result = subprocess.run(
        ["nix", "eval", "--json", f"{ROOT}#{attribute}"],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def test_endeavour_uses_only_orion_and_apollo():
    machines = nix_eval("nixosConfigurations.endeavour.config.nix.buildMachines")
    assert [machine["hostName"] for machine in machines] == [
        "orion-builder",
        "apollo-builder",
    ]


def test_kepler_never_uses_itself_as_a_remote_builder():
    machines = nix_eval("nixosConfigurations.kepler.config.nix.buildMachines")
    assert [machine["hostName"] for machine in machines] == ["orion-builder", "apollo-builder"]


def test_kepler_retains_existing_ssh_authorization():
    keys = nix_eval(
        "nixosConfigurations.kepler.config.users.users.erik.openssh.authorizedKeys.keys"
    )
    assert any(key.endswith("nix-builder@laptop") for key in keys)


def test_recipe_pool_excludes_the_target_and_kepler():
    for target, endpoints in (
        ("orion", ["apollo-builder"]),
        ("apollo", ["orion-builder"]),
        ("kepler", ["orion-builder", "apollo-builder"]),
        ("endeavour", ["orion-builder", "apollo-builder"]),
    ):
        result = subprocess.run(
            ["just", "--no-dotenv", "_builders", target],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        specs = [spec.strip().split() for spec in result.stdout.strip().split(";")]
        assert [spec[0] for spec in specs] == [
            f"ssh-ng://erik@{endpoint}:2222" for endpoint in endpoints
        ]
        assert all(spec[2] == "/home/erik/.ssh/id_ed25519" for spec in specs)
        for spec in specs:
            if "orion-builder" in spec[0]:
                assert spec[1] == "i686-linux,x86_64-linux,aarch64-linux"
                assert spec[3:5] == ["16", "2"]
                assert "kvm" not in spec[5].split(",")
            else:
                assert spec[1] == "i686-linux,x86_64-linux"
                assert spec[3:5] == ["6", "1"]
                assert set(spec[5].split(",")) == {"big-parallel", "benchmark", "kvm", "nixos-test"}


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
