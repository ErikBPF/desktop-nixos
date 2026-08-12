from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/networking/pangolin-newt.nix"
JUSTFILE = ROOT / "justfile"


def test_newt_release_is_checksum_pinned():
    module = MODULE.read_text()

    assert 'version = "1.15.0";' in module
    assert "sha256-" in module
    assert "releases/download/${version}/newt_linux_amd64" in module


def test_newt_keeps_credentials_and_reports_health():
    module = MODULE.read_text()

    assert 'StateDirectory = "pangolin-newt";' in module
    assert 'CONFIG_FILE = "/var/lib/pangolin-newt/config.json";' in module
    assert 'HEALTH_FILE = "/run/pangolin-newt/healthy";' in module
    assert "NEWT_METRICS_PROMETHEUS_ENABLED = \"true\";" in module
    assert 'NEWT_ADMIN_ADDR = "127.0.0.1:2112";' in module
    assert "LoadCredential" in module
    assert "NoNewPrivileges = true;" in module
    assert "ProtectSystem = \"strict\";" in module


def test_home_ingress_is_least_privilege_and_multi_site():
    module = MODULE.read_text()

    for value in (
        "private-resources:",
        "home-ingress:",
        "mode: host",
        'destination: "${fleet.hosts.discovery.ip}"',
        'tcp-ports: "443"',
        'udp-ports: ""',
        "disable-icmp: true",
        'alias: "*.${fleet.ingress.homelab.zone}"',
        "- home-discovery",
        "- home-kepler",
        "- ${email}",
    ):
        assert value in module


def test_discovery_and_kepler_run_independent_sites():
    module = MODULE.read_text()

    for host, site in (("discovery", "home-discovery"), ("kepler", "home-kepler")):
        config = (ROOT / f"modules/hosts/{host}/default.nix").read_text()
        assert "m.nixos.pangolin-newt" in config
        assert "services.pangolinNewt = {" in config
        assert "enable = true;" in config
        assert f'siteName = "{site}";' in config

    assert 'allowedTCPPorts = [2112]' not in module
    assert 'allowedUDPPorts' not in module


def test_remote_verification_checks_persisted_credentials_health_and_metrics():
    justfile = JUSTFILE.read_text()

    for value in (
        "verify-pangolin-newt target:",
        "systemctl is-active pangolin-newt.service",
        "/var/lib/pangolin-newt/config.json",
        "/run/pangolin-newt/healthy",
        "http://127.0.0.1:2112/metrics",
        "provisioningKey",
        "grep '^# HELP ' >/dev/null",
        "--resolve",
        "/api/health",
        '.database == "ok"',
    ):
        assert value in justfile


def test_boot_deploy_copies_directly_on_the_lan():
    recipe = JUSTFILE.read_text().split("deploy-rs-boot target:", 1)[1].split(
        "deploy-boot target", 1
    )[0]

    assert "--fast-connection true" in recipe
