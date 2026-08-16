from pathlib import Path


HARDWARE = Path("modules/hosts/endeavour/hardware.nix").read_text()


def test_tpm_unlock_keeps_password_fallback():
    assert 'passwordFile = "/tmp/luks-password.txt";' in HARDWARE
    assert 'settings.crypttabExtraOpts = ["tpm2-device=auto"];' in HARDWARE
