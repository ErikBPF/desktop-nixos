import json
import shlex
import subprocess
from pathlib import Path
import xml.etree.ElementTree as ET


ROOT = Path(__file__).parents[2]
MODULE = ROOT / "modules/hosts/orion/wazuh-agent.nix"
JUSTFILE = ("\n".join(p.read_text() for p in [ROOT / "justfile", *sorted((ROOT / "just").glob("*.just"))]))


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
    assert '"/var/log/wazuh-host:/var/log/wazuh-host:ro"' in source
    assert '/var/log/journal' not in source
    assert '/run/log/journal' not in source
    assert '/etc/machine-id' not in source
    assert 'services.rsyslogd' in source
    assert 'defaultConfig = "";' in source
    assert '$inputname == "imjournal"' in source
    assert '$!_SYSTEMD_UNIT == "sshd.service"' in source
    assert 'StateFile=' in source
    assert 'IgnorePreviousMessages="on"' in source
    assert 'Ratelimit.Interval="0"' in source
    assert 'services.logrotate.settings' in source
    assert 'copytruncate' not in source
    assert 'syslog.service' in source
    assert '/wazuh-config-mount/etc/ossec.conf:ro' in source
    assert "sops-nix.service" not in source
    assert "--privileged" not in source
    assert "--pid=host" not in source
    assert "docker.sock" not in source
    assert "podman.sock" not in source
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
    assert "127.0.0.1" in recipe
    assert "PreferredAuthentications=none" in recipe
    assert "journalctl" in recipe
    assert "sshd.service" in recipe
    assert "active-responses.log" not in recipe
    assert "/var/log/wazuh-host/sshd.log" in recipe
    assert "systemd-run" in recipe
    assert "StandardOutput=journal" in recipe
    assert "for _ in {1..30}" in recipe
    assert "orion-canary" in recipe
    assert "just verify-wazuh-agent-canary" in recipe


def test_only_host_ssh_journal_is_collected():
    path = MODULE.with_name("wazuh-agent.xml")
    assert path.exists(), "host SSH collection configuration is missing"
    root = ET.parse(path).getroot()
    collectors = root.findall("localfile")
    assert len(collectors) == 1
    collector = collectors[0]
    assert collector.findtext("location") == "/var/log/wazuh-host/sshd.log"
    assert collector.findtext("log_format") == "syslog"
    assert not collector.findall("filter")
    assert root.findtext("rootcheck/disabled") == "yes"
    assert root.findtext("syscheck/disabled") == "yes"
    assert root.findtext("wodle[@name='syscollector']/disabled") == "yes"
    assert root.findtext("sca/enabled") == "no"
    assert not root.findall(".//command")


def test_alert_verifiers_tolerate_partial_final_line_without_false_positive():
    alert = {"agent": {"name": "orion-canary"},
             "location": "/var/log/wazuh-host/sshd.log",
             "rule": {"groups": ["sshd"]}, "full_log": "fixture-marker"}
    for line in JUSTFILE.splitlines():
        if "jq " not in line or '.agent.name == "orion-canary"' not in line:
            continue
        command = shlex.split(line.strip().split(" >/dev/null", 1)[0])
        command = ["fixture-marker" if arg == "$marker" else arg for arg in command]
        for matches in (True, False):
            record = alert | {"agent": {"name": "orion-canary" if matches else "other"}}
            result = subprocess.run(command, input=json.dumps(record) + '\n{"agent":',
                                    text=True, capture_output=True)
            assert (result.returncode == 0) == matches, result.stderr


def test_vault_recovery_pulls_in_agent_after_dependency_failure():
    source = MODULE.read_text().split('systemd.services.podman-wazuh-agent = {', 1)[1].split('\n    };', 1)[0]
    assert 'wantedBy = ["wazuh-agent-vault.service"]' in source, (
        'Vault can recover after its boot timeout without retrying the dependent agent'
    )


def test_enrollment_verifies_pinned_manager_without_changing_identity_or_feed():
    root = ET.parse(MODULE.with_name("wazuh-agent.xml")).getroot()
    assert root.findtext("client/enrollment/server_ca_path") == "/var/ossec/etc/enrollment-ca.pem"
    source = MODULE.read_text()
    assert 'WAZUH_REGISTRATION_SERVER = "wazuh-manager-master-0"' in source
    assert '"--add-host=wazuh-manager-master-0:192.168.10.250"' in source
    assert '${./wazuh-enrollment-ca.pem}:/var/ossec/etc/enrollment-ca.pem:ro' in source
    assert '"${stateDir}/client.keys:/var/ossec/etc/client.keys"' in source
    assert 'WAZUH_AGENT_NAME = "orion-canary"' in source


def test_public_enrollment_pin_matches_authenticated_manager_receipt():
    certificate = MODULE.with_name("wazuh-enrollment-ca.pem")
    result = subprocess.run(["openssl", "x509", "-in", str(certificate),
                             "-noout", "-fingerprint", "-sha256"],
                            check=True, capture_output=True, text=True)
    assert "3D:53:33:FB:58:6F:22:DA:2A:72:71:23:9F:F4:3A:EB:B0:F9:20:3F:35:2D:0A:66:76:94:00:B4:34:9B:05:27" in result.stdout
    assert "PRIVATE KEY" not in certificate.read_text()
    assert "modules/hosts/orion/wazuh-enrollment-ca.pem" in (ROOT / ".graphifyignore").read_text()
