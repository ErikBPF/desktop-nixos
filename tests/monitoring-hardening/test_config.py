from pathlib import Path


ROOT = Path(__file__).parents[2]


def test_monitoring_refuses_to_start_without_vault_mount():
    config = (ROOT / "modules/hosts/discovery/compose.nix").read_text()

    assert 'podman-compose-monitoring' in config
    assert 'mountpoint --quiet /home/erik/vault' in config


def test_alloy_pushes_to_kubernetes_backends():
    config = (ROOT / "modules/services/alloy.nix").read_text()

    assert "config.fleet.hosts.discovery.tailscaleIp" not in config
    assert 'https://loki.homelab.pastelariadev.com/loki/api/v1/push' in config
    assert 'https://prometheus.homelab.pastelariadev.com/api/v1/write' in config


def test_vector_pushes_to_kubernetes_loki():
    config = (ROOT / "modules/services/vector-logs.nix").read_text()

    assert "config.fleet.hosts.discovery.tailscaleIp" not in config
    assert 'endpoint = "https://loki.homelab.pastelariadev.com"' in config


def test_cluster_log_collector_uses_in_cluster_loki():
    config = (ROOT / "modules/hosts/kepler/k3s-cluster.nix").read_text()

    assert 'http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push' in config
    assert "100.76.140.121:3100" not in config


def test_operator_metric_clients_use_kubernetes_prometheus():
    terminal = (ROOT / "modules/terminal/grafatui.nix").read_text()
    recipes = (ROOT / "justfile").read_text()

    for config in (terminal, recipes):
        assert "http://discovery:9090" not in config
        assert "https://prometheus.homelab.pastelariadev.com" in config


def test_monitoring_health_gate_includes_metrics_and_logs_backends():
    config = (ROOT / "modules/hosts/discovery/compose.nix").read_text()

    assert "http://${config.fleet.hosts.discovery.tailscaleIp}:3100/ready" in config
    assert "--retry-all-errors" in config
    assert (
        'secretSpecRuntimeHealthContainers.monitoring = '
        '["prometheus" "grafana" "healthchecks" "scrutiny-influxdb" "scrutiny"];'
    ) in config
