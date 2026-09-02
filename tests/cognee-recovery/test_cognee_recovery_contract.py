from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_kepler_prepares_stable_cognee_backup_path() -> None:
    source = (ROOT / "modules/hosts/kepler/nas.nix").read_text()

    assert '"d /fast/k8s/cognee-backups 0770 root root -"' in source
