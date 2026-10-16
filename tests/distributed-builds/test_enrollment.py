"""Daemon enrollment and native SSH endpoint policy; no keys or RPCs accessed."""

import json
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
CONSUMERS = ("endeavour", "kepler", "discovery")
PUBLIC_KEYS = {
    "kepler": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINSN7mhPQHSpTqO3+P0aHQqKQppNM5g3P3/9iS+9vFa4 nix-builder@kepler",
    "discovery": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE0321n0iMNbD6lmtYo8UpNa/7Ebm1tgsHqYhldC0BY6 nix-builder@discovery",
}


def test_consumers_explicitly_enroll_both_builders():
    for host in CONSUMERS:
        source = (ROOT / f"modules/hosts/{host}/default.nix").read_text()
        assert "nix.distributedBuildsOrion.enable = true;" in source, host
        assert "nix.distributedBuildsApollo.enable = true;" in source, host
        assert "distributedBuildsKepler" not in source, host


@pytest.fixture(scope="module")
def policies():
    # Evaluate the real module with pinned NixOS/sops modules, avoiding unrelated
    # desktop/HM derivations. Targeted dry gates check composed host configs separately.
    expression = r'''
      let
        flake = builtins.getFlake (toString ./.);
        module = (import ./modules/services/distributed-builds.nix {
          config = { username = "erik"; flake.fleet = flake.fleet; };
          self = ./.;
        }).flake.modules.nixos.distributed-builds;
        evaluate = host: let
          config = (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ module flake.inputs.sops-nix.nixosModules.sops {
              networking.hostName = host;
              system.stateVersion = "25.11";
              nix.settings = { max-jobs = "auto"; cores = 0; };
              nix.distributedBuildsOrion.enable = host != "pathfinder";
              nix.distributedBuildsApollo.enable = host != "pathfinder";
            } ];
          }).config;
        in {
          machines = config.nix.buildMachines;
          maxJobs = config.nix.settings.max-jobs;
          cores = config.nix.settings.cores;
          serve = config.nix.sshServe;
          trustedUsers = config.nix.settings.trusted-users;
          authorized = config.users.users.nix-ssh.openssh.authorizedKeys.keys or [];
          serverSsh = config.services.openssh.extraConfig;
          ssh = config.programs.ssh.extraConfig;
          knownHosts = config.programs.ssh.knownHosts;
          secrets = builtins.mapAttrs (_: secret: {
            inherit (secret) path owner group mode key;
            sopsFile = toString secret.sopsFile;
          }) config.sops.secrets;
        };
      in builtins.listToAttrs (map (host: {
        name = host; value = evaluate host;
      }) [ "endeavour" "kepler" "discovery" "orion" "apollo" "pathfinder" ])
    '''
    result = subprocess.run(
        ["nix", "eval", "--impure", "--json", "--expr", expression],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
        timeout=180,
    )
    return json.loads(result.stdout)


def test_native_pool_and_self_exclusion(policies):
    for host, policy in policies.items():
        expected = [] if host == "pathfinder" else [
            f"{builder}-builder" for builder in ("orion", "apollo") if builder != host
        ]
        assert [machine["hostName"] for machine in policy["machines"]] == expected
        for machine in policy["machines"]:
            assert machine["protocol"] == "ssh-ng"
            if machine["hostName"] == "orion-builder":
                assert set(machine["systems"]) == {"i686-linux", "x86_64-linux", "aarch64-linux"}
                assert machine["maxJobs"] == 16
                assert machine["speedFactor"] == 4
                assert set(machine["supportedFeatures"]) == {"benchmark", "big-parallel", "nixos-test"}
            else:
                assert set(machine["systems"]) == {"i686-linux", "x86_64-linux"}
                assert machine["maxJobs"] == 6
                assert machine["speedFactor"] == 1
                assert set(machine["supportedFeatures"]) == {"benchmark", "big-parallel", "kvm", "nixos-test"}


def test_only_enrolled_consumers_get_one_local_fallback_job(policies):
    for host, policy in policies.items():
        assert policy["maxJobs"] == (1 if host in CONSUMERS else "auto")
        assert policy["cores"] == (1 if host in CONSUMERS else 0)


def test_server_identity_is_root_only_sops_not_personal_key(policies):
    for host in ("kepler", "discovery"):
        policy = policies[host]
        name = f"nix-builders/{host}/ssh-key"
        secret = policy["secrets"][name]
        assert (secret["owner"], secret["group"], secret["mode"]) == ("root", "root", "0400")
        assert secret["key"] == name
        assert secret["sopsFile"].endswith("/secrets/sops/secrets.yaml")
        assert {machine["sshKey"] for machine in policy["machines"]} == {secret["path"]}
        assert {machine["sshUser"] for machine in policy["machines"]} == {"nix-ssh"}
    for machine in policies["endeavour"]["machines"]:
        assert machine["sshUser"] == "erik"
        assert machine["sshKey"] == "/home/erik/.ssh/id_ed25519"


def test_server_keys_only_enter_native_untrusted_builder_endpoints(policies):
    for host, policy in policies.items():
        assert policy["serve"]["enable"] == (host in ("orion", "apollo"))
        if host not in ("orion", "apollo"):
            continue
        assert policy["serve"]["protocol"] == "ssh-ng"
        assert policy["serve"]["trusted"] is False
        assert set(policy["serve"]["keys"]) == set(PUBLIC_KEYS.values())
        assert "nix-ssh" not in policy["trustedUsers"]
        assert set(policy["authorized"]) == set(PUBLIC_KEYS.values())
        endpoint = policy["serverSsh"]
        assert "Match User nix-ssh" in endpoint
        assert "nix-daemon --stdio" in endpoint
        assert "ForceCommand " in endpoint
        for restriction in ("AllowTcpForwarding no", "AllowAgentForwarding no", "X11Forwarding no", "PermitTTY no", "PermitTunnel no"):
            assert restriction in endpoint
        assert "Match All" in endpoint


def test_aliases_use_native_lan_match_and_strict_public_pins(policies):
    pins = {
        "orion": ("192.168.10.220", "100.72.85.73", "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAdaVn+4eIM6ogsg5KsMbhCXAX7fK5n1xoqMEl6endXh"),
        "apollo": ("192.168.10.174", "100.77.14.27", "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKgV3yaYhtTk4F3qNyMnfDsFFcbnLuCnZaU9XaHfHQm2"),
    }
    for host in (*CONSUMERS, "orion", "apollo"):
        policy = policies[host]
        ssh = policy["ssh"]
        assert "accept-new" not in ssh
        assert "ProxyCommand" not in ssh
        assert ssh.rstrip().endswith("Host *")
        for builder, (lan, tail, public_key) in pins.items():
            match = f"Match originalhost {builder}-builder localnetwork 192.168.10.0/24"
            assert match in ssh
            assert ssh.index(f"HostName {lan}") < ssh.index(f"HostName {tail}")
            for option in ("Port 2222", "BatchMode yes", "ConnectTimeout 8", "StrictHostKeyChecking yes", f"HostKeyAlias [{lan}]:2222"):
                assert option in ssh
            assert any(
                f"[{lan}]:2222" in known["hostNames"] and known["publicKey"] == public_key
                for known in policy["knownHosts"].values()
            )
