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


def test_laptop_uses_primary_and_spillover_builders():
    machines = nix_eval("nixosConfigurations.laptop.config.nix.buildMachines")
    actual = [
        {
            "hostName": machine["hostName"],
            "maxJobs": machine["maxJobs"],
            "speedFactor": machine["speedFactor"],
            "systems": machine["systems"],
        }
        for machine in machines
    ]
    expected = json.loads((Path(__file__).parent / "expected-laptop.json").read_text())
    assert actual == expected
    assert "kvm" in machines[0]["supportedFeatures"]
    assert "kvm" not in machines[1]["supportedFeatures"]
    assert "nixos-test" not in machines[1]["supportedFeatures"]


def test_kepler_never_uses_itself_as_a_remote_builder():
    machines = nix_eval("nixosConfigurations.kepler.config.nix.buildMachines")
    assert all(machine["hostName"] != "192.168.10.230" for machine in machines)


def test_kepler_authorizes_the_dedicated_builder_key():
    keys = nix_eval(
        "nixosConfigurations.kepler.config.users.users.erik.openssh.authorizedKeys.keys"
    )
    assert any(key.endswith("nix-builder@laptop") for key in keys)


def test_recipe_builders_use_explicit_hardened_ssh_ports():
    for target in ("kepler", "orion", "laptop"):
        result = subprocess.run(
            ["just", "_builders", target],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        assert "@192.168.10." in result.stdout
        assert ":2222 " in result.stdout


def test_builder_hosts_bootstrap_keys_once_then_reject_changes():
    extra_config = nix_eval("nixosConfigurations.laptop.config.programs.ssh.extraConfig")
    assert extra_config.count("StrictHostKeyChecking accept-new") == 2
