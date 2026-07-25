from pathlib import Path


MODULE = (
    Path(__file__).parents[2] / "modules" / "hosts" / "kepler" / "networking.nix"
).read_text()


def test_postgres_exporter_is_tailnet_only():
    assert "interfaces.tailscale0.allowedTCPPorts = [9187];" in MODULE
    global_ports = MODULE.split("allowedTCPPorts = [", 1)[1].split("];", 1)[0]
    assert "9187" not in global_ports
