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
