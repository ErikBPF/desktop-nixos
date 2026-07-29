from pathlib import Path


JUSTFILE = (Path(__file__).parents[2] / "justfile").read_text()


def test_live_wazuh_verifier_is_bounded_and_value_safe():
    recipe = JUSTFILE.split("verify-wazuh-siem:", 1)[1].split("\n\n", 1)[0]

    assert "wazuh-logtest" in recipe
    assert "UniFi Protect" in recipe
    assert "podman ps" in recipe
    assert "wazuh_unifi_last_event_seconds" in recipe
    assert "192.168.10.230:5514" in recipe
