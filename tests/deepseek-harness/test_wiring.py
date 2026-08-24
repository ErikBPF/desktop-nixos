from pathlib import Path


ROOT = Path(__file__).parents[2]


def test_endeavour_gets_deepseek_web_yolo_profile():
    module_path = ROOT / "modules/dev/deepseek-harness.nix"
    assert module_path.exists()

    flake = (ROOT / "flake.nix").read_text()
    endeavour = (ROOT / "modules/hosts/endeavour/default.nix").read_text()
    pathfinder = (ROOT / "modules/hosts/pathfinder/default.nix").read_text()
    module = module_path.read_text()

    assert 'url = "github:ErikBPF/deepseek-harness-flake";' in flake
    assert "m.home.deepseek-harness" in endeavour
    assert "m.home.deepseek-harness" not in pathfinder
    assert "inputs.deepseek-harness-flake.packages.${system}.default" in module
    assert 'DSH_TELEMETRY_DISABLED = "1";' in module
    assert 'dp = "env DSH_PERMISSION_MODE=danger-full-access dsh web";' in module
