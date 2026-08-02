from pathlib import Path


BRAVE = Path("modules/browser/brave.nix").read_text()


def test_brave_does_not_require_an_overridable_package():
    assert "commandLineArgs" not in BRAVE
