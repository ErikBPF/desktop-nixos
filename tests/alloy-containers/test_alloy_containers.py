from pathlib import Path


ROOT = Path(__file__).parents[2]
MODULE = ROOT / "modules/services/alloy-containers.nix"
DISCOVERY = ROOT / "modules/hosts/discovery/default.nix"
KEPLER = ROOT / "modules/hosts/kepler/default.nix"
KEPLER_COMPOSE = ROOT / "modules/hosts/kepler/compose.nix"
ORION = ROOT / "modules/hosts/orion/default.nix"
ORION_COMPOSE = ROOT / "modules/hosts/orion/compose.nix"
JUSTFILE = ROOT / "justfile"


def test_container_metrics_cover_rootless_podman_and_docker():
    module = MODULE.read_text()
    discovery = DISCOVERY.read_text()

    assert "DynamicUser = lib.mkForce false" in module
    assert 'User = "root"' in module
    assert "containerd_host" in module
    assert 'target_label = "host"' in module
    assert "m.nixos.alloy-containers" in discovery
    assert 'containerSocket = "unix:///run/docker.sock"' in discovery
    assert 'containerdSocket = "/run/docker/containerd/containerd.sock"' in discovery


def test_container_name_labels_have_a_live_verification_recipe():
    recipe = JUSTFILE.read_text()

    assert "verify-container-metrics:" in recipe
    assert 'container_last_seen{name!=""} or podman_container_info{name!=""}' in recipe
    assert "jq --arg host \"$host\"" in recipe
    for host in ("discovery", "kepler", "orion"):
        assert host in recipe


def test_podman_hosts_scrape_the_dedicated_exporter_without_privileged_cadvisor():
    module = MODULE.read_text()

    assert "podmanExporter" in module
    assert '"127.0.0.1:9882"' in module
    assert '"job"         = "podman"' in module

    for host_file, compose_file in (
        (KEPLER, KEPLER_COMPOSE),
        (ORION, ORION_COMPOSE),
    ):
        host = host_file.read_text()
        compose = compose_file.read_text()
        assert "podmanExporter = true" in host
        assert "containerSocket" not in host
        assert '"monitoring"' in compose
