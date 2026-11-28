from pathlib import Path

ROOT = Path(__file__).parents[2]


def test_only_official_flash_next_starts_on_orion():
    host = (ROOT / "modules/hosts/orion/default.nix").read_text()
    stacks = (ROOT / "modules/hosts/orion/compose.nix").read_text()
    rollout = (ROOT / "just/servarr.just").read_text()

    assert "m.nixos.orion-strata-flash-next" in host
    assert '"ai-models"' not in stacks
    assert "orion) stacks=(shared monitoring sync)" in rollout


def test_official_unit_preserves_the_running_profile():
    path = ROOT / "modules/hosts/orion/strata-flash-next.nix"
    assert path.exists(), "Flash Next must have a declarative owner"
    unit = path.read_text()
    for required in (
        '"--network host"',
        '"--group-add keep-groups"',
        '"-e STRATA_MAX_TOP_LOGPROBS=160"',
        '"-v /opt/models:/models:ro"',
        '"-v /opt/models/strata:/s"',
        "sha256:92f309c51b52cef8762867848f1529dee821624f23cd5df38455e819538f762f",
        "--profile /s/home/.local/state/strata/launch/q2_0-120k.json",
        '"--parallel 2"',
        'LimitMEMLOCK = "infinity"',
        'RestartSec = "15s"',
        'TimeoutStopSec = "90s"',
    ):
        assert required in unit
    assert "force = true" not in unit
    assert "--device /dev/kfd --device /dev/dri" in unit
    assert 'flakeConfig.fleet.hosts.orion.tailscaleIp' in unit


def test_probe_names_official_runtime_but_preserves_alert_metrics():
    probe = (ROOT / "modules/hosts/discovery/monitoring.nix").read_text()
    assert "strata-flash-next-health-probe" in probe
    assert "strata_chat_health" in probe
    assert "strata_chat_health_probe_timestamp_seconds" in probe
    assert "http://100.72.85.73:8080/health" in probe
