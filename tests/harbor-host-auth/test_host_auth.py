from pathlib import Path


ROOT = Path(__file__).parents[2]
MODULE = ROOT / "modules/services/harbor-reader.nix"
DISCOVERY = ROOT / "modules/hosts/discovery/default.nix"
ENDEAVOUR = ROOT / "modules/hosts/endeavour/default.nix"
USER = ROOT / "modules/user.nix"
KEPLER = ROOT / "modules/hosts/kepler/default.nix"
K3S = ROOT / "modules/hosts/kepler/k3s-cluster.nix"
DISCOVERY_VAULT = ROOT / "modules/hosts/discovery/vault.nix"
JUSTFILE = ROOT / "justfile"


def test_reader_credentials_are_runtime_only_and_host_scoped():
    module = MODULE.read_text()

    assert 'secret/data/fleet/harbor/readers/${config.networking.hostName}' in module
    assert 'roleIdFile = lib.mkOption' in module
    assert 'secretIdFile = lib.mkOption' in module
    assert 'RuntimeDirectory = "harbor-reader"' in module
    assert 'RuntimeDirectoryPreserve = "restart"' in module
    assert 'after = ["network-online.target" "sops-nix.service" "tailscaled-autoconnect.service"]' in module
    assert 'wants = ["network-online.target" "tailscaled-autoconnect.service"]' in module
    assert 'perms = "0400"' in module
    assert "ExecStartPost" in module
    assert "for _ in {1..60}" in module
    assert "[[ -s ${destination} ]]" in module
    assert 'ephemeral = true' not in module
    assert 'environment.etc' not in module


def test_only_proven_hosts_enable_reader_projection():
    discovery = DISCOVERY.read_text()
    endeavour = ENDEAVOUR.read_text()
    kepler = KEPLER.read_text()

    for source in (discovery, endeavour, kepler):
        assert "m.nixos.harbor-reader" in source
        assert "services.harborReader" in source
        assert "enable = true" in source
    assert 'format = "docker"' in discovery
    assert 'format = "docker"' in endeavour
    assert 'format = "k3s"' in kepler


def test_k3s_consumes_runtime_registry_auth_not_store_text():
    source = K3S.read_text()

    assert 'source = "/run/harbor-reader"' in source
    assert 'mountPoint = "/run/harbor-reader"' in source
    assert '"--private-registry=/run/harbor-reader/registries.yaml"' in source
    assert 'environment.etc."rancher/k3s/registries.yaml".text' not in source
    assert 'harbor-reader = {' in source


def test_docker_auth_is_owned_by_the_runtime_principal():
    module = MODULE.read_text()
    discovery = DISCOVERY.read_text()
    discovery_vault = DISCOVERY_VAULT.read_text()
    endeavour = ENDEAVOUR.read_text()
    user = USER.read_text()

    assert 'user = lib.mkOption' in module
    assert 'authPath = lib.mkOption' in module
    assert 'User = cfg.user' in module
    assert '"L+ ${cfg.authPath}' in module
    assert '/root/.docker/config.json' not in module

    assert 'user = flakeConfig.username;' in discovery
    assert 'authPath = "/home/${flakeConfig.username}/.docker/config.json";' in discovery
    assert 'owner = username;' in discovery_vault

    assert 'user = flakeConfig.username;' in endeavour
    assert 'authPath = "/run/user/1000/containers/auth.json";' in endeavour
    assert endeavour.count('owner = flakeConfig.username;') >= 2
    assert "uid = 1000;" in user


def test_fleet_reader_approles_rotate_directly_into_sops():
    recipe = JUSTFILE.read_text().split(
        "capture-harbor-fleet-reader-approle-secrets:", 1
    )[1].split("\n# ", 1)[0]

    assert "svc-homelab-iac-openbao-harbor-fleet-readers-publisher" in recipe
    assert "discovery endeavour kepler" in recipe
    assert "svc-desktop-nixos-$identity-harbor-reader" in recipe
    assert "secret-id-accessor/destroy" in recipe
    assert 'key_prefix="openbao_harbor_reader_${identity}"' in recipe
    assert '${key_prefix}_role_id' in recipe
    assert '${key_prefix}_secret_id' in recipe
    assert recipe.count("sops set --value-stdin") == 2
    assert 'echo "$credentials"' not in recipe
