from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/services/alloy.nix"


def test_textfile_directory_is_writable_by_rootless_compose_owner():
    text = MODULE.read_text()
    assert "d /var/lib/node-exporter-textfile 0755 erik users - -" in text


def test_filesystem_collector_skips_remote_nfs_mounts():
    text = MODULE.read_text()

    assert (
        'mount_points_exclude = "^/(dev|proc|run/credentials/.+|sys|var/lib/docker/.+|mnt/nfs)($|/)"'
        in text
    )
