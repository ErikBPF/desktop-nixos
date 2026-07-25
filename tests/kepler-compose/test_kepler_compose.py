from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/hosts/kepler/compose.nix"


def test_enabled_stacks_include_backup_and_exclude_empty_profile():
    text = MODULE.read_text()
    assert '"sync"' in text
    assert '"docs-search"' not in text
