from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
K3S = (ROOT / "modules/hosts/kepler/k3s-cluster.nix").read_text()
FIREWALL = (ROOT / "modules/hosts/kepler/networking.nix").read_text()


def test_wazuh_node_kernel_and_vip_forwarding_are_host_owned():
    assert 'boot.kernel.sysctl."vm.max_map_count" = 262144;' in K3S
    assert 'listen ${ingressVip}:1514' in K3S
    assert 'listen ${ingressVip}:1515' in K3S
    assert 'listen ${ingressVip}:5514 udp' in K3S
    assert "wazuhAgentNodePort = 31514;" in K3S
    assert "wazuhRegistrationNodePort = 31515;" in K3S
    assert "wazuhSyslogNodePort = 30514;" in K3S


def test_kepler_firewall_retains_wazuh_public_ports():
    for port in ("1514", "1515", "5514"):
        assert port in FIREWALL
