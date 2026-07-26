from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_kepler_runs_the_discovery_dead_mans_switch():
    kepler = (ROOT / "modules/hosts/kepler/default.nix").read_text()
    assert "m.nixos.dead-mans-switch" in kepler
    assert "services.deadMansSwitch = {" in kepler
    assert "enable = true;" in kepler
    assert 'checkUrl = "https://id.' in kepler


def test_notification_identifies_the_actual_observer():
    module = (ROOT / "modules/services/dead-mans-switch.nix").read_text()
    assert "${config.networking.hostName} dead-man's-switch" in module
