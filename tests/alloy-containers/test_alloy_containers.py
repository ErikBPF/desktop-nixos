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


def test_docker_container_metrics_wait_for_docker_without_requiring_it():
    module = MODULE.read_text()

    assert 'after = ["docker.service"]' in module
    assert 'wants = ["docker.service"]' in module
    assert 'requires = ["docker.service"]' not in module


def test_container_name_labels_have_a_live_verification_recipe():
    recipe = JUSTFILE.read_text()

    assert "verify-container-metrics:" in recipe
    assert "query=container_last_seen or podman_container_info" in recipe
    assert "raw_containers=%s named_containers=%s" in recipe
    assert "failed=1" in recipe
    assert 'exit "$failed"' in recipe
    assert "jq --arg host \"$host\"" in recipe
    for host in ("discovery", "kepler", "orion"):
        assert host in recipe


def test_container_and_cache_diagnostics_preserve_startup_evidence():
    recipe = JUSTFILE.read_text()

    assert "systemctl show alloy docker" in recipe
    assert "ActiveState,SubState,Result,ActiveEnterTimestamp" in recipe
    assert "journalctl -b -u alloy" in recipe
    assert "remote_write|prometheus" in recipe
    assert "getent ahostsv4 prometheus.homelab.pastelariadev.com" in recipe
    assert "127.0.0.1:12345/metrics" in recipe
    assert "diagnose orion nix-cache-builder.service" in recipe


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
