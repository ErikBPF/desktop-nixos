from pathlib import Path


ROOT = Path(__file__).parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text()


def test_sops_keys_are_consumed_without_plaintext_copies():
    module = read("modules/services/sops.nix")
    assert "copySopsSecrets" not in module
    assert '.ssh/id_ed25519"' in module
    assert '.ssh/id_rsa"' in module


def test_vault_renders_are_not_world_readable():
    vault = read("modules/hosts/discovery/_vault-agent.nix")
    assert 'RuntimeDirectoryMode = "0750"' in vault
    assert 'Group = "vault-consumers"' in vault
    assert 'perms = "0444"' not in vault


def test_haos_storage_does_not_require_home_traversal():
    module = read("modules/hosts/discovery/haos.nix")
    domain = read("modules/hosts/discovery/haos-domain.xml")
    assert 'fileSystems."/srv/vms"' in module
    assert "haos-perms-fix" not in module
    assert "chmod 711" not in module
    assert "/srv/vms/haos_ova-17.1.qcow2" in module
    assert "/srv/vms/haos_ova-17.1.qcow2" in domain


def test_nix_cache_firewall_is_interface_scoped():
    module = read("modules/services/nix-cache.nix")
    assert "networking.firewall.allowedTCPPorts" not in module
    assert "networking.firewall.interfaces.enp4s0.allowedTCPPorts" in module
    assert "networking.firewall.interfaces.tailscale0.allowedTCPPorts" in module


def test_upgrade_health_units_extend_immutable_base():
    module = read("modules/services/upgrade-health-check.nix")
    assert "extraCriticalUnits" in module
    for path in (ROOT / "modules/hosts").glob("*/default.nix"):
        assert "modules.upgradeHealthCheck.criticalUnits =" not in path.read_text()


def test_vault_concerns_are_split():
    vault = read("modules/hosts/discovery/vault.nix")
    assert "./_vault-agent.nix" in vault
    assert (ROOT / "modules/hosts/discovery/_vault-agent.nix").exists()
