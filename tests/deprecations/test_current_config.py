from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_antigravity_replaces_removed_gemini_cli():
    desktop = (ROOT / "modules/packages/desktop.nix").read_text()

    assert "antigravity-cli" in desktop
    assert "gemini-cli" not in desktop


def test_nixvim_explicitly_uses_the_host_nixpkgs():
    nvim = (ROOT / "modules/dev/nvim.nix").read_text()

    assert "nixpkgs.source = inputs.nixpkgs;" in nvim


def test_gemini_container_preserves_xdg_session_variables():
    gemini = (ROOT / "modules/hosts/orion/gemini.nix").read_text()

    assert "setSessionVariables = true;" in gemini
