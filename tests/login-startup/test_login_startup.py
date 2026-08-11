from pathlib import Path


FIRST_BOOT = Path("modules/services/first-boot.nix").read_text()
SOPS = Path("modules/services/sops.nix").read_text()


def test_first_boot_does_not_restart_retired_overlay():
    assert "netbird" not in FIRST_BOOT.lower()


def test_system_sops_key_is_available_before_home_mounts():
    assert 'sops.age.keyFile = "/var/lib/sops-nix/key.txt"' in SOPS
    assert 'SYSTEM_TARGET="/var/lib/sops-nix/key.txt"' in FIRST_BOOT
    assert 'install -m 0600 "$TARGET" "$SYSTEM_TARGET"' in FIRST_BOOT
    assert 'deps = ["specialfs"];' in FIRST_BOOT
    assert 'setupSecrets.deps = lib.mkAfter ["distributeSopsKey"]' in FIRST_BOOT
