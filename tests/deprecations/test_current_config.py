from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_retired_ai_clis_stay_absent():
    desktop = (ROOT / "modules/packages/desktop.nix").read_text()

    assert "gemini-cli" not in desktop
    assert "antigravity-cli" not in desktop


def test_nixvim_explicitly_uses_the_host_nixpkgs():
    nvim = (ROOT / "modules/dev/nvim.nix").read_text()

    assert "nixpkgs.source = inputs.nixpkgs;" in nvim
