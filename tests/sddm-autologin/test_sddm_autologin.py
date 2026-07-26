from pathlib import Path


SDDM = Path("modules/desktop/sddm.nix").read_text()


def test_autologin_starts_hyprland_for_erik():
    assert 'defaultSession = "hyprland-uwsm";' in SDDM
    assert "autoLogin = {" in SDDM
    assert "enable = true;" in SDDM.split("autoLogin = {", 1)[1].split("};", 1)[0]
    assert 'user = "erik";' in SDDM
