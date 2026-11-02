from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_kepler_prepares_stable_cognee_backup_path() -> None:
    source = (ROOT / "modules/hosts/kepler/nas.nix").read_text()

    assert "systemd.services.cognee-backup-path" in source
    assert 'after = ["local-fs.target"]' in source
    assert 'before = ["nfs-server.service"]' in source
    assert "install -d -m 0770 -o erik -g users /fast/k8s/cognee-backups" in source

