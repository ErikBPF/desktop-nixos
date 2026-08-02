from pathlib import Path


NETWORKING = (Path(__file__).parents[2] / "modules/hosts/kepler/networking.nix").read_text()
COMPOSE = (Path(__file__).parents[2] / "modules/hosts/kepler/compose.nix").read_text()


def test_kepler_opens_wazuh_agent_and_syslog_ports():
    assert "1514 # Wazuh agent events" in NETWORKING
    assert "1515 # Wazuh agent enrollment" in NETWORKING
    assert "5514 # UniFi SIEM syslog" in NETWORKING


def test_kepler_manages_security_stack():
    assert '"security"' in COMPOSE
