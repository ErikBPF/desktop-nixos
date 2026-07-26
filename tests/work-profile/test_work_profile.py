from pathlib import Path


ROOT = Path(__file__).parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text()


def test_work_profile_composes_portable_agents():
    work = read("modules/profiles/work.nix")

    assert "flake.modules.nixos.work" in work
    assert "m.nixos.kace-agent" in work
    assert "m.nixos.trend-agent" in work
    assert "m.nixos.cloudflare-warp" in work


def test_endeavour_imports_only_work_profile():
    endeavour = read("modules/hosts/endeavour/default.nix")

    assert "m.nixos.work" in endeavour
    assert "m.nixos.endeavour-ampagent" not in endeavour
    assert "m.nixos.endeavour-trend" not in endeavour


def test_laptop_imports_work_profile():
    laptop = read("modules/hosts/laptop/default.nix")

    assert "m.nixos.work" in laptop


def test_trend_waits_for_runtime_libraries_before_starting():
    trend = read("modules/services/trend-agent.nix")

    assert 'PathExists = "/opt/ds_agent/lib/dsa_core.so";' in trend


def test_trend_installer_can_start_basecamp():
    trend = read("modules/services/trend-agent.nix")

    assert '[[ "$1" == start' not in trend
    assert trend.count('Environment = "LD_LIBRARY_PATH=${agentLibraryPath}";') == 3


def test_trend_installer_retries_until_fully_complete():
    trend = read("modules/services/trend-agent.nix")

    assert "touch /var/lib/trend-install-complete" in trend
    assert 'ConditionPathExists = "!/var/lib/trend-install-complete";' in trend
    assert "dsa_query -c GetAgentStatus" in trend
    assert "AgentStatus.agentState: green" in trend
