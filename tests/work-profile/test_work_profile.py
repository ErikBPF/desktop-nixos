import os
from pathlib import Path
import subprocess


ROOT = Path(__file__).parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text()


def test_work_agents_exist_only_in_the_ubuntu_guest():
    retired = [
        "modules/profiles/work.nix",
        "modules/services/cloudflare-warp.nix",
        "modules/services/kace-agent.nix",
        "modules/services/trend-agent.nix",
        "modules/hosts/endeavour/trend.nix",
    ]

    assert all(not (ROOT / path).exists() for path in retired)
    assert "m.nixos.cloudflare-warp" not in read("modules/packages/desktop.nix")
    assert "m.nixos.work" not in read("modules/hosts/endeavour/default.nix")


def test_work_agent_ports_are_not_opened_by_nixos():
    nix = "\n".join(path.read_text() for path in (ROOT / "modules").rglob("*.nix"))

    assert "allowedTCPPorts = [4118]" not in nix


def test_ubuntu_guest_deploy_verifies_apt_owned_agents():
    deploy = read("scripts/deploy-ubuntu-work-profile.sh")

    for package in ["cloudflare-warp", "ds-agent"]:
        assert package in deploy
    for service in ["warp-svc.service", "ds_agent.service", "tmxbc.service"]:
        assert service in deploy
    assert "ampagent" not in deploy
    assert "konea.service" not in deploy
    assert "apt-get install -y cloudflare-warp" not in deploy
    assert "apt-get install -y ampagent" not in deploy
    assert "apt-get install -y ds-agent" not in deploy


def test_kace_removal_uses_ssh_and_propagates_failure(tmp_path):
    script = ROOT / "scripts/remove-ubuntu-work-kace.sh"
    assert script.exists(), "Guest KACE removal script is missing"
    ssh = tmp_path / "ssh"
    ssh.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$SSH_ARGS"\nexit "$SSH_EXIT"\n')
    ssh.chmod(0o755)
    args_file = tmp_path / "ssh-args"
    env = {
        **os.environ,
        "PATH": f"{tmp_path}:{os.environ['PATH']}",
        "SSH_ARGS": str(args_file),
    }
    env.pop("UBUNTU_WORK_SSH_TARGET", None)

    for target, exit_code in [("erik@192.168.122.74", 0), ("test@guest", 42)]:
        env["SSH_EXIT"] = str(exit_code)
        if target == "test@guest":
            env["UBUNTU_WORK_SSH_TARGET"] = target
        result = subprocess.run(["bash", str(script)], env=env, capture_output=True)

        assert result.returncode == exit_code, result.stderr.decode()
        assert args_file.read_text().splitlines() == [
            "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=yes", target,
            "sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y ampagent",
        ]


def test_nixos_has_no_work_agent_bootstrap_or_secrets():
    assert "add-ampagent:" not in read("justfile")
    assert "trend-installer" not in read(".sops.yaml")
    assert not (ROOT / "secrets/sops/trend-installer.sh").exists()
    assert "kace_token:" not in read("secrets/sops/secrets.yaml")
