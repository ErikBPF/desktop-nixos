from pathlib import Path


ENDEAVOUR = Path("modules/hosts/endeavour/default.nix").read_text()


def test_endeavour_restores_its_real_touchpad_right_button():
    assert 'environment.etc."libinput/local-overrides.quirks".text' in ENDEAVOUR
    assert "MatchVendor=0x093A" in ENDEAVOUR
    assert "MatchProduct=0x0255" in ENDEAVOUR
    assert "MatchDMIModalias=dmi:*:svnPositivoBahia-VAIO:pnVJBK1BF11X-*:*" in ENDEAVOUR
    assert "AttrEventCode=+BTN_RIGHT" in ENDEAVOUR
