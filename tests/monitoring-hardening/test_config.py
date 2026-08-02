from pathlib import Path


ROOT = Path(__file__).parents[2]


def test_monitoring_refuses_to_start_without_vault_mount():
    config = (ROOT / "modules/hosts/discovery/compose.nix").read_text()

    assert 'podman-compose-monitoring' in config
    assert 'mountpoint --quiet /home/erik/vault' in config


def test_alloy_pushes_to_discovery_tailnet_ip():
    config = (ROOT / "modules/services/alloy.nix").read_text()

    assert "config.fleet.hosts.discovery.tailscaleIp" in config
    assert 'http://${discoveryTs}:3100/loki/api/v1/push' in config
    assert 'http://${discoveryTs}:9090/api/v1/write' in config


def test_vector_pushes_to_discovery_tailnet_ip():
    config = (ROOT / "modules/services/vector-logs.nix").read_text()

    assert "config.fleet.hosts.discovery.tailscaleIp" in config
    assert 'endpoint = "http://${discoveryTs}:3100"' in config


def test_monitoring_health_gate_includes_metrics_and_logs_backends():
    config = (ROOT / "modules/hosts/discovery/compose.nix").read_text()

    assert "http://${config.fleet.hosts.discovery.tailscaleIp}:3100/ready" in config
    assert "--retry-all-errors" in config
    assert (
        'secretSpecRuntimeHealthContainers.monitoring = '
        '["prometheus" "grafana" "healthchecks" "scrutiny-influxdb" "scrutiny"];'
    ) in config
