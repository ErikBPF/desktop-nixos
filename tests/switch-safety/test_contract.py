from pathlib import Path


ROOT = Path(__file__).parents[2]


def test_live_switch_preserves_boot_blessing_and_telstar_capture():
    boot = (ROOT / "modules/hardware/systemd-boot-counting.nix").read_text()
    bless = boot.split("systemd.services.systemd-bless-boot", 1)[1]
    assert "restartIfChanged = false;" in bless
    assert "stopIfChanged = false;" in bless
    assert "systemd-bless-boot status" in bless

    telstar = (ROOT / "modules/hosts/discovery/telstar-capture.nix").read_text()
    capture = telstar.split("systemd.services.telstar-capture", 1)[1]
    assert "restartIfChanged = false;" in capture
    assert "stopIfChanged = false;" in capture


def test_klipper_accepts_large_gcode_uploads():
    module = (ROOT / "modules/services/klipper-host.nix").read_text()
    assert 'services.nginx.clientMaxBodySize = "1024m";' in module
