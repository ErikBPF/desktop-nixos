import json
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).parents[2]
FLEET = json.loads((ROOT / "fleet.json").read_text())["hosts"]


def nix_eval(attribute: str):
    result = subprocess.run(
        ["nix", "eval", "--json", f".#{attribute}"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


@pytest.mark.parametrize("host", ["voyager", "vanguard", "telstar"])
def test_oci_ssh_is_open_only_on_tailscale(host):
    config = f"nixosConfigurations.{host}.config"

    assert nix_eval(f"{config}.services.openssh.openFirewall") is False
    assert 2222 in nix_eval(
        f"{config}.networking.firewall.interfaces.tailscale0.allowedTCPPorts"
    )
    assert 2222 not in nix_eval(f"{config}.networking.firewall.allowedTCPPorts")


@pytest.mark.parametrize("host", ["voyager", "vanguard"])
def test_live_oci_deploys_use_stable_tailnet_addresses(host):
    assert nix_eval(f"deploy.nodes.{host}.hostname") == FLEET[host]["tailscaleIp"]
    assert nix_eval(f"deploy.nodes.{host}.magicRollback") is False
