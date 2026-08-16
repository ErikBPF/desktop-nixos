from pathlib import Path


SDDM = Path("modules/desktop/sddm.nix").read_text()
XSERVER = Path("modules/services/xserver.nix").read_text()


def test_sddm_requires_login_before_starting_hyprland():
    assert 'defaultSession = "hyprland-uwsm";' in SDDM
    assert "autoLogin = {" not in SDDM


def test_console_uses_the_desktop_keyboard_layout():
    assert "console.useXkbConfig = true;" in XSERVER
