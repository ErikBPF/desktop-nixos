from pathlib import Path


ROOT = Path(__file__).parents[2]
MODULE = ROOT / "modules/services/harbor-reader.nix"
DISCOVERY = ROOT / "modules/hosts/discovery/default.nix"
ENDEAVOUR = ROOT / "modules/hosts/endeavour/default.nix"
KEPLER = ROOT / "modules/hosts/kepler/default.nix"
K3S = ROOT / "modules/hosts/kepler/k3s-cluster.nix"
JUSTFILE = ROOT / "justfile"


def test_reader_credentials_are_runtime_only_and_host_scoped():
    module = MODULE.read_text()

    assert 'secret/data/fleet/harbor/readers/${config.networking.hostName}' in module
    assert 'roleIdFile = lib.mkOption' in module
    assert 'secretIdFile = lib.mkOption' in module
    assert 'RuntimeDirectory = "harbor-reader"' in module
    assert 'perms = "0400"' in module
    assert "ExecStartPost" in module
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
