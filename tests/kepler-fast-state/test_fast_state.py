from pathlib import Path


ROOT = Path(__file__).parents[2]
MODULE = ROOT / "modules/hosts/kepler/k3s-cluster.nix"
HARDWARE = ROOT / "modules/hosts/kepler/hardware.nix"
JUSTFILE = ("\n".join(p.read_text() for p in [ROOT / "justfile", *sorted((ROOT / "just").glob("*.just"))]))


def test_microvms_use_fast_pool_with_mount_ordering():
    module = MODULE.read_text()

    assert 'microvm.stateDir = "/fast/microvms";' in module
    assert "disk = 32768;" in module
    assert "disk = 131072;" in module
    assert module.count('unitConfig.RequiresMountsFor = "/fast/microvms";') == 3
    assert '"microvm-set-booted@"' in module
    assert '"install-microvm-${name}"' in module


def test_existing_etcd_members_start_in_parallel():
    module = MODULE.read_text()

    assert '"cp-2" = "cp-1"' not in module
    assert '"cp-3" = "cp-2"' not in module
    assert 'lib.genAttrs workerNames (_: "cp-1")' in module


def test_disk_resize_is_grow_only_and_offline():
    justfile = JUSTFILE
    hardware = HARDWARE.read_text()

    recipe = justfile.split("resize-kepler-k3s-disks:", 1)[1]
    assert "e2fsprogs" in hardware
    assert "systemctl stop microvms.target" in recipe
    assert "truncate -s" in recipe
    assert "e2fsck -fp" in recipe
    assert "resize2fs" in recipe
    assert "current > wanted" in recipe
    assert "current == wanted" not in recipe

