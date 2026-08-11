from pathlib import Path


FIRST_BOOT = Path("modules/services/first-boot.nix").read_text()


def test_first_boot_does_not_restart_retired_overlay():
    assert "netbird" not in FIRST_BOOT.lower()
