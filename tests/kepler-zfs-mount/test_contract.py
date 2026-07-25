from pathlib import Path


MODULE = (
    Path(__file__).parents[2] / "modules" / "hosts" / "kepler" / "hardware.nix"
).read_text()


def test_explicit_mounts_disable_legacy_mount_all():
    assert 'fileSystems."/fast"' in MODULE
    assert 'fileSystems."/bulk"' in MODULE
    assert "systemd.services.zfs-mount.enable = false;" in MODULE
