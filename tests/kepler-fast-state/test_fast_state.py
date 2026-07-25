from pathlib import Path


ROOT = Path(__file__).parents[2]
MODULE = ROOT / "modules/hosts/kepler/k3s-cluster.nix"
HARDWARE = ROOT / "modules/hosts/kepler/hardware.nix"
JUSTFILE = ROOT / "justfile"


def test_microvms_use_fast_pool_with_mount_ordering():
    module = MODULE.read_text()

    assert 'microvm.stateDir = "/fast/microvms";' in module
    assert "disk = 32768;" in module
    assert "disk = 131072;" in module
    assert module.count('unitConfig.RequiresMountsFor = "/fast/microvms";') == 3
    assert '"microvm-set-booted@"' in module
    assert '"install-microvm-${name}"' in module


def test_disk_resize_is_grow_only_and_offline():
    justfile = JUSTFILE.read_text()
    hardware = HARDWARE.read_text()

    recipe = justfile.split("resize-kepler-k3s-disks:", 1)[1]
    assert "e2fsprogs" in hardware
    assert "systemctl stop microvms.target" in recipe
    assert "truncate -s" in recipe
    assert "e2fsck -f" in recipe
    assert "resize2fs" in recipe
    assert "current > wanted" in recipe


def test_migration_is_copy_verify_switch_finalize():
    justfile = JUSTFILE.read_text()

    assert "prepare-kepler-fast-state:" in justfile
    assert "rsync -aHAXS --numeric-ids --checksum --dry-run" in justfile
    assert "finalize-kepler-fast-state:" in justfile
    assert 'test "$state_dir" = /fast/microvms' in justfile
