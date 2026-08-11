from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_offsite_probes_use_the_public_ha_endpoint():
    for host in ("kepler", "vanguard"):
        config = (ROOT / f"modules/hosts/{host}/default.nix").read_text()
        assert "m.nixos.dead-mans-switch" in config
        assert "services.deadMansSwitch" in config
        assert 'checkUrl = "https://${config.flake.fleet.services.ha.fqdn}";' in config
        assert "https://id." not in config


def test_notification_identifies_the_actual_observer():
    module = (ROOT / "modules/services/dead-mans-switch.nix").read_text()
    assert "${config.networking.hostName} dead-man's-switch" in module
