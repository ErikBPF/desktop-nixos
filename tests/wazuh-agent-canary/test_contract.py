from pathlib import Path


ROOT = Path(__file__).parents[2]
MODULE = ROOT / "modules/hosts/orion/wazuh-agent.nix"


def test_orion_canary_uses_fresh_vault_enrollment_and_host_journal():
    assert MODULE.exists()
    source = MODULE.read_text()
    orion = (ROOT / "modules/hosts/orion/default.nix").read_text()

    assert "m.nixos.orion-wazuh-agent" in orion
    assert "wazuh/wazuh-agent:4.14.7@sha256:150e7af098fbe34ec7d4825a0943ec2ab87525bff3d62488f104094c3354032e" in source
    assert 'image = "docker.io/wazuh/wazuh-agent:4.14.7@sha256:' in source
    assert 'WAZUH_MANAGER_SERVER = "192.168.10.250"' in source
    assert 'WAZUH_AGENT_NAME = "orion-canary"' in source
    assert 'secret/data/platform/wazuh/wazuh-authd-pass' in source
    assert 'environmentFiles = ["/run/wazuh-agent/agent.env"]' in source
    assert "/var/log/journal:/var/log/journal:ro" in source
    assert "/etc/machine-id:/etc/machine-id:ro" in source
    assert "sops-nix.service" not in source
    assert "--privileged" not in source
