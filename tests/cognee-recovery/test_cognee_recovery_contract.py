from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_kepler_prepares_stable_cognee_backup_path() -> None:
    source = (ROOT / "modules/hosts/kepler/nas.nix").read_text()

    assert '"d /fast/k8s/cognee-backups 0770 erik users -"' in source


def test_kepler_has_safe_legacy_retrieval_cutover() -> None:
    source = (ROOT / "justfile").read_text()

    assert "kepler-retire-legacy-retrieval:" in source
    assert "bge-m3 bge-reranker-v2-m3" in source
    assert "aedf3b34836dc57289583142adcf2b93836cda0736ac8e6ce43691b9c2c67170" in source
    assert ".Config.Image | endswith($digest)" in source
