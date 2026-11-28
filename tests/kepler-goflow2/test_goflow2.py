import re
from pathlib import Path


ROOT = Path(__file__).parents[2]
MODULE = (ROOT / "modules/hosts/kepler/goflow2.nix").read_text()
NETWORKING = (ROOT / "modules/hosts/kepler/networking.nix").read_text()
MONITORING = (ROOT / "modules/hosts/kepler/monitoring.nix").read_text()


def test_service_runs_goflow2_on_ipfix_port():
    assert 'systemd.services.goflow2 = {' in MODULE
    assert "netflow://${keplerIp}:2055" in MODULE
    assert "-addr=127.0.0.1:8081" in MODULE
    assert 'Restart = "always";' in MODULE
    assert 'MemoryMax = "256M";' in MODULE


def test_firewall_chain_is_source_restricted_and_idempotent():
    assert "iptables -N kepler-ipfix 2>/dev/null || true" in NETWORKING
    assert "iptables -F kepler-ipfix" in NETWORKING
    assert "iptables -A kepler-ipfix -s 192.168.10.1/32 -p udp -m udp --dport 2055 -j ACCEPT" in NETWORKING
    assert "iptables -A kepler-ipfix -j REJECT" in NETWORKING
    assert "iptables -D INPUT -p udp -m udp --dport 2055 -j kepler-ipfix 2>/dev/null || true" in NETWORKING
    assert "iptables -A INPUT -p udp -m udp --dport 2055 -j kepler-ipfix" in NETWORKING


def test_2055_is_not_a_generic_allowed_udp_port():
    """The source restriction would disappear if 2055 moved to allowedUDPPorts."""
    udp_block = re.search(r"allowedUDPPorts = \[(.*?)\];", NETWORKING, re.S).group(1)
    ports = [line.split("#")[0].strip() for line in udp_block.splitlines()]
    assert "2055" not in ports


def test_alloy_scrapes_goflow2_with_stable_job_name():
    assert 'prometheus.scrape "goflow2" {' in MONITORING
    assert '"job"         = "goflow2",' in MONITORING
    assert '"__address__" = "127.0.0.1:8081",' in MONITORING
    assert "prometheus.remote_write.prometheus.receiver" in MONITORING


def test_no_credentials_in_collector_sources():
    pattern = re.compile(
        r"password|passwd|api[_-]?key|token|bearer|secret|sops",
        re.IGNORECASE,
    )
    assert not pattern.search(MODULE)
    assert not pattern.search(MONITORING)
