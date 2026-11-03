from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_notification_identifies_the_actual_observer():
    module = (ROOT / "modules/services/dead-mans-switch.nix").read_text()
    assert "${config.networking.hostName} dead-man's-switch" in module


def test_external_probe_can_be_force_fired_without_exposing_webhook():
    module = (ROOT / "modules/services/dead-mans-switch.nix").read_text()
    tree = "\n".join(
        p.read_text()
        for p in [ROOT / "justfile", *sorted((ROOT / "just").glob("*.just"))]
    )
    recipe = tree.split("test-vanguard-dead-mans-switch:", 1)[1].split("\n\n", 1)[0]

    assert 'url="${cfg.checkUrl}"' in module
    assert 'if [ "$#" -gt 0 ]; then url="$1"; fi' in module
    assert 'name = "dead-mans-switch-probe"' in module
    assert "--fail --silent" in module
    assert "notification delivered" in module
    assert "for _ in {1..6}" in recipe
    assert "systemctl stop dead-mans-switch.timer" in recipe
    assert "http://127.0.0.1:9" in recipe
    assert "notification delivered" in recipe
    assert "dead-mans-switch-probe" in recipe
    assert "cat " not in recipe
