from pathlib import Path


THEMING = Path("modules/desktop/theming.nix").read_text()


def test_gtk_uses_fast_adwaita_icon_theme():
    assert "package = pkgs.adwaita-icon-theme;" in THEMING
    assert 'name = "Adwaita";' in THEMING
    assert "papirus-icon-theme" not in THEMING
