from pathlib import Path


ALLOY = Path(__file__).parents[2] / "modules/services/alloy.nix"


def test_alloy_self_metrics_use_fleet_hostname_as_instance():
    module = ALLOY.read_text()
    block = module.split('prometheus.scrape "alloy_self"', 1)[1].split(
        'prometheus.scrape "tailscale"', 1
    )[0]

    assert 'instance    = "${config.networking.hostName}"' in block
