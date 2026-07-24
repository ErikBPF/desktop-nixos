from pathlib import Path


def test_orion_upgrade_diagnostics_cover_network_and_generation_state():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("diagnose-gateway-reachability target:", 1)[1].split(
        "\n\n", 1
    )[0]

    for check in (
        "tailscaleIp",
        "systemd-run --machine=gemini --pipe --wait",
        "ip route",
        "ip rule",
        "table 52",
        "tailscale version",
        "RouteAll",
        "/dev/tcp/$gw/443",
    ):
        assert check in recipe


def test_orion_route_recovery_disables_subnet_routes_and_verifies_physical_path():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("recover-orion-tailscale-routes:", 1)[1].split(
        "\n\n", 1
    )[0]

    for check in (
        "tailscale set --accept-routes=false",
        "dev enp4s0",
        "/dev/tcp/$gw/443",
    ):
        assert check in recipe


def test_orion_does_not_accept_subnet_routes():
    networking = (
        Path(__file__).parents[2] / "modules/hosts/orion/networking.nix"
    ).read_text()

    assert 'extraSetFlags = lib.mkForce ["--accept-dns=true" "--accept-routes=false"]' in networking
