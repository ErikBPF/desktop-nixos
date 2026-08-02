from pathlib import Path


JUSTFILE = (Path(__file__).parents[2] / "justfile").read_text()


def test_unifi_capture_is_bounded_and_omits_payloads():
    recipe = JUSTFILE.split("capture-unifi-siem:", 1)[1].split("\n\n", 1)[0]

    assert "timeout 60 tcpdump" in recipe
    assert "nix shell nixpkgs#tcpdump" in recipe
    assert "-c 10" in recipe
    assert "udp dst port 5514" in recipe
    assert "udp dst port 514" in recipe
    assert "archive_before=" in recipe
    assert "archive_after=" in recipe
    assert "archive_delta=" in recipe
    assert "cef_lines=" in recipe
    assert "podman port wazuh-manager 514/udp" in recipe
    assert "NetworkSettings.Networks" in recipe
    assert "program:" in recipe
    assert "event_metadata=none" in recipe
    assert "full_log" not in recipe
    assert " -A " not in recipe
    assert " -X " not in recipe


def test_unifi_probe_is_synthetic_and_isolates_the_failed_hop():
    recipe = JUSTFILE.split("probe-unifi-siem:", 1)[1].split("\n\n", 1)[0]

    assert "/dev/udp/127.0.0.1/5514" in recipe
    assert "/dev/udp/127.0.0.1/514" in recipe
    assert "synthetic" in recipe
    assert "host_delta=" in recipe
    assert "container_delta=" in recipe
    assert "full_log" not in recipe
