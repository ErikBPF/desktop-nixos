import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FLEET = json.loads((ROOT / "fleet.json").read_text())


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
        FLEET["hosts"][host]["tailscaleIp"] for host in ("orion", "kepler")
    ]
    for machine in machines:
        assert machine["sshUser"] == "erik"
        assert machine["sshKey"] == "/home/erik/.ssh/id_ed25519"
        assert machine["protocol"] == "ssh-ng"
    assert machines[0]["systems"] == ["x86_64-linux", "aarch64-linux"]
    assert machines[0]["maxJobs"] == 16
    assert machines[0]["supportedFeatures"] == ["nixos-test", "benchmark", "big-parallel", "kvm"]
    assert machines[1]["systems"] == ["x86_64-linux"]
    assert machines[1]["maxJobs"] == 2
    assert machines[1]["supportedFeatures"] == ["benchmark", "big-parallel"]


def test_kepler_never_uses_itself_as_a_remote_builder():
    machines = nix_eval("nixosConfigurations.kepler.config.nix.buildMachines")
    assert all(machine["hostName"] != FLEET["hosts"]["kepler"]["tailscaleIp"] for machine in machines)


def test_enabled_builder_hosts_never_offload_to_themselves():
    for host in ("orion", "kepler"):
        expression = f'''let f = builtins.getFlake {json.dumps(str(ROOT))}; in
          (f.nixosConfigurations.{host}.extendModules {{ modules = [
            {{ nix.distributedBuildsOrion.enable = true;
               nix.distributedBuildsKepler.enable = true; }}
          ]; }}).config.nix.buildMachines'''
        machines = json.loads(subprocess.check_output(
            ["nix", "eval", "--impure", "--json", "--expr", expression], text=True
        ))
        assert all(machine["hostName"] not in (
            FLEET["hosts"][host]["ip"], FLEET["hosts"][host]["tailscaleIp"]
        ) for machine in machines)


def test_kepler_authorizes_the_dedicated_builder_key():
    keys = nix_eval(
        "nixosConfigurations.kepler.config.users.users.erik.openssh.authorizedKeys.keys"
    )
    assert any(key.endswith("nix-builder@laptop") for key in keys)


def test_recipe_builders_use_inventory_tailscale_addresses_and_hardened_ports():
    for target in ("kepler", "orion", "endeavour"):
        result = subprocess.run(
            ["just", "_builders", target],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        builders = [host for host in ("orion", "kepler") if host != target]
        expected = [
            f"ssh-ng://erik@{FLEET['hosts'][host]['tailscaleIp']}:2222"
            for host in builders
        ]
        assert [entry.split()[0] for entry in result.stdout.split(";")] == expected


def test_builder_hosts_configure_accept_new_for_lan_and_tailnet():
    extra_config = nix_eval("nixosConfigurations.endeavour.config.programs.ssh.extraConfig")
    for host in ("orion", "kepler"):
        addresses = FLEET["hosts"][host]
        assert f"Host {addresses['ip']} {addresses['tailscaleIp']}\n  Port 2222\n  StrictHostKeyChecking accept-new" in extra_config
    assert "StrictHostKeyChecking no" not in extra_config
    assert "UserKnownHostsFile /dev/null" not in extra_config
