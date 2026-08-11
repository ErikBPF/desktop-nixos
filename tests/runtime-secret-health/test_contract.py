from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def source(relative: str) -> str:
    path = ROOT / relative
    return path.read_text() if path.exists() else ""


def test_discovery_and_kepler_report_sops_runtime_secret_readiness():
    module = source("modules/services/runtime-secret-health.nix")

    for host in ("discovery", "kepler"):
        config = source(f"modules/hosts/{host}/default.nix")
        assert "m.nixos.runtime-secret-health" in config
    assert "sops_runtime_secrets_ready" in module
    assert 'ConditionPathExists = "/var/lib/node-exporter-textfile"' in module


def test_discovery_reports_required_vault_render_freshness():
    module = source("modules/hosts/discovery/runtime-health.nix")
    discovery = source("modules/hosts/discovery/default.nix")

    assert "m.nixos.discovery-runtime-health" in discovery
    assert "vault_agent_required_renders_ready" in module
    assert "vault_agent_render_last_success_seconds" in module
    for name in ("discord.env", "shared-db.env", "shared-grafana.env", "ai-serving.env"):
        assert f"/run/vault-agent/{name}" in module


def test_discovery_runs_litellm_semantic_probe():
    module = source("modules/hosts/discovery/runtime-health.nix")

    assert "litellm_semantic_ready" in module
    assert '"ha-agent-qwen4b"' in module
    assert "/v1/chat/completions" in module
    assert "docker exec -i litellm" in module
