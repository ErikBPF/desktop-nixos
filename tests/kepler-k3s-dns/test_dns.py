from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_guests_resolve_internal_homelab_services_before_public_fallbacks():
    module = (ROOT / "modules/hosts/kepler/k3s-cluster.nix").read_text()
    assert 'networking.nameservers = ["192.168.10.210" "1.1.1.1" "9.9.9.9"];' in module
