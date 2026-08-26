from pathlib import Path


ROOT = Path(__file__).parents[2]


def test_discovery_legacy_monitoring_stack_is_retired():
    config = (ROOT / "modules/hosts/discovery/compose.nix").read_text()

    assert 'podman-compose-monitoring' not in config
    assert '"monitoring" # grafana' not in config
    assert 'secretSpecRuntimeProfiles.monitoring' not in config


def test_discovery_alloy_scrapes_local_application_metrics():
    config = (ROOT / "modules/hosts/discovery/monitoring.nix").read_text()

    for job, target in (
        ("adguard", "127.0.0.1:9618"),
        ("cloudflared", "127.0.0.1:20241"),
        ("litellm", "127.0.0.1:4000"),
        ("postgres-discovery", "127.0.0.1:9187"),
    ):
        assert f'"job"         = "{job}"' in config
        assert f'"__address__" = "{target}"' in config
    assert 'credentials_file = "/run/vault-agent/litellm-metrics.token"' in config
    assert 'regex         = "up|cloudflared_tunnel_.*"' in config


def test_discovery_alloy_replaces_remote_federation_scrapes():
    config = (ROOT / "modules/hosts/discovery/monitoring.nix").read_text()

    for job, target in (
        ("llamacpp", "100.72.85.73:8080"),
        ("node-vanguard", "100.90.247.79:9100"),
        ("node-voyager", "100.105.38.10:9100"),
    ):
        assert f'"job"         = "{job}"' in config
        assert f'"__address__" = "{target}"' in config
    assert "nvidia-gpu" not in config


def test_kepler_alloy_scrapes_its_local_postgres_exporter():
    config = (ROOT / "modules/hosts/kepler/monitoring.nix").read_text()

    assert '"job"         = "postgres-kepler"' in config
    assert '"__address__" = "100.94.239.46:9187"' in config


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
