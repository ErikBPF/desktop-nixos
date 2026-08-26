from pathlib import Path


ROOT = Path(__file__).parents[2]
MODULE = ROOT / "modules/hosts/orion/wazuh-agent.nix"
JUSTFILE = (ROOT / "justfile").read_text()


def test_orion_canary_uses_fresh_vault_enrollment():
    assert MODULE.exists()
    source = MODULE.read_text()
    orion = (ROOT / "modules/hosts/orion/default.nix").read_text()
    cluster = (ROOT / "modules/hosts/kepler/k3s-cluster.nix").read_text()

    assert "m.nixos.orion-wazuh-agent" in orion
    assert "wazuh/wazuh-agent:4.14.7@sha256:150e7af098fbe34ec7d4825a0943ec2ab87525bff3d62488f104094c3354032e" in source
    assert 'image = "docker.io/wazuh/wazuh-agent:4.14.7@sha256:' in source
    assert 'WAZUH_MANAGER_SERVER = "192.168.10.250"' in source
    assert 'WAZUH_AGENT_NAME = "orion-canary"' in source
    assert 'secret/data/platform/wazuh/wazuh-authd-pass' in source
    assert 'key = "wazuh_agent_role_id"' in source
    assert 'key = "wazuh_agent_secret_id"' in source
    assert "vault_approle_platform" not in source
    assert 'environmentFiles = ["/run/wazuh-agent/agent.env"]' in source
    assert '"d ${runtimeDir} 0700 root root -"' in source
    assert "RuntimeDirectory =" not in source
    assert 'RuntimeDirectoryPreserve = "yes"' in source
    assert '"f ${stateDir}/client.keys 0600 999 999 -"' in source
    assert "hostJournal" not in source
    assert "/var/log/journal" not in source
    assert "sops-nix.service" not in source
    assert "--privileged" not in source
    assert "networking.firewall.allowedTCPPorts = [6443 443 1514 1515];" in cluster
    assert "networking.firewall.allowedUDPPorts = [5514];" in cluster


def test_live_canary_verifier_checks_runtime_and_attributed_alert():
    recipe = JUSTFILE.split("verify-wazuh-agent-canary:", 1)[1].split("\n\n", 1)[0]
    assert "wazuh-agent-vault.service podman-wazuh-agent.service" in recipe
    assert "agent_control -lc" in recipe
    assert "orion-canary" in recipe
    assert "alerts.json" in recipe


def test_canary_probe_is_harmless_bounded_and_attributed():
    recipe = JUSTFILE.split("probe-wazuh-agent-canary:", 1)[1].split("\n\n", 1)[0]
    assert "192.0.2.1" in recipe
    assert "for _ in {1..30}" in recipe
    assert "orion-canary" in recipe
    assert "just verify-wazuh-agent-canary" in recipe
