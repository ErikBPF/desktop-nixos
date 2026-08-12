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


def test_endeavour_uses_primary_and_spillover_builders():
    machines = nix_eval("nixosConfigurations.endeavour.config.nix.buildMachines")
    assert [machine["hostName"] for machine in machines] == [
        "192.168.10.220",
        "192.168.10.230",
    ]


def test_kepler_never_uses_itself_as_a_remote_builder():
    machines = nix_eval("nixosConfigurations.kepler.config.nix.buildMachines")
    assert all(machine["hostName"] != "192.168.10.230" for machine in machines)


def test_kepler_authorizes_the_dedicated_builder_key():
    keys = nix_eval(
        "nixosConfigurations.kepler.config.users.users.erik.openssh.authorizedKeys.keys"
    )
    assert any(key.endswith("nix-builder@laptop") for key in keys)


def test_recipe_builders_use_explicit_hardened_ssh_ports():
    for target in ("kepler", "orion", "endeavour"):
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
    extra_config = nix_eval("nixosConfigurations.endeavour.config.programs.ssh.extraConfig")
    assert "Host 192.168.10.220\n  Port 2222\n  StrictHostKeyChecking accept-new" in extra_config
    assert "Host 192.168.10.230\n  Port 2222\n  StrictHostKeyChecking accept-new" in extra_config
