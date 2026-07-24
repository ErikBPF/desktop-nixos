from pathlib import Path


ROOT = Path(__file__).parents[2]
MODULE = ROOT / "modules/hosts/kepler/k3s-cluster.nix"
JUSTFILE = ROOT / "justfile"


def test_microvms_use_fast_pool_with_mount_ordering():
    module = MODULE.read_text()

    assert 'microvm.stateDir = "/fast/microvms";' in module
    assert 'unitConfig.RequiresMountsFor = "/fast/microvms";' in module


def test_migration_is_copy_verify_switch_finalize():
    justfile = JUSTFILE.read_text()

    assert "prepare-kepler-fast-state:" in justfile
    assert "rsync -aHAXS --numeric-ids --checksum --dry-run" in justfile
    assert "finalize-kepler-fast-state:" in justfile
    assert 'test "$state_dir" = /fast/microvms' in justfile
