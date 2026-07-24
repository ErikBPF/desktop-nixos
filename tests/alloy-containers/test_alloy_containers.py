from pathlib import Path


ROOT = Path(__file__).parents[2]
MODULE = ROOT / "modules/services/alloy-containers.nix"
DISCOVERY = ROOT / "modules/hosts/discovery/default.nix"
JUSTFILE = ROOT / "justfile"


def test_container_metrics_cover_rootless_podman_and_docker():
    module = MODULE.read_text()
    discovery = DISCOVERY.read_text()

    assert "DynamicUser = lib.mkForce false" in module
    assert 'User = "root"' in module
    assert 'target_label = "host"' in module
    assert "m.nixos.alloy-containers" in discovery
    assert 'containerSocket = "unix:///run/docker.sock"' in discovery


def test_container_name_labels_have_a_live_verification_recipe():
    recipe = JUSTFILE.read_text()

    assert "verify-container-metrics:" in recipe
    assert 'container_last_seen{name!=""}' in recipe
    assert "jq --arg host \"$host\"" in recipe
    for host in ("discovery", "kepler", "orion"):
        assert host in recipe
