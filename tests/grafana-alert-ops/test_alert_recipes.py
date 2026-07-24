import pathlib


ROOT = pathlib.Path(__file__).resolve().parents[2]


def test_endeavour_upgrade_has_diagnostics_and_retry_target():
    justfile = (ROOT / "justfile").read_text()
    assert "diagnose endeavour nixos-upgrade.service" in justfile
    assert (
        "endeavour-upgrade) host=endeavour; "
        "unit=nixos-upgrade.service; action=reset ;;"
    ) in justfile
