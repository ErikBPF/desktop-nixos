from pathlib import Path


FIRST_BOOT = Path("modules/services/first-boot.nix").read_text()
NETBIRD = Path("modules/networking/netbird-client.nix").read_text()


def test_first_boot_does_not_wait_for_netbird():
    assert "systemctl restart --no-block netbird-login.service" in FIRST_BOOT
    assert '!/var/lib/sops-first-boot-complete' in FIRST_BOOT


def test_netbird_login_has_a_startup_timeout():
    assert 'TimeoutStartSec = "30s";' in NETBIRD
