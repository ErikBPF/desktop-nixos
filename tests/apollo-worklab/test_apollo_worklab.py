import json
import os
from pathlib import Path
import stat
import subprocess
import textwrap


ROOT = Path(__file__).resolve().parents[2]
JUSTFILE = (ROOT / "justfile").read_text()


def read(relative: str) -> str:
    path = ROOT / relative
    assert path.exists(), f"missing {relative}"
    return path.read_text()


def recipe(name: str) -> str:
    marker = next(
        (line for line in JUSTFILE.splitlines() if line == f"{name}:" or line.startswith(f"{name} ")),
        None,
    )
    assert marker is not None
    return JUSTFILE.split(marker, 1)[1].split("\n\n", 1)[0]


def test_apollo_keeps_host_tools_without_global_language_modules() -> None:
    apollo = read("modules/hosts/apollo/default.nix")

    for module in ("nix-index", "hermes-client", "opencode-client"):
        assert f"m.nixos.{module}" in apollo

    for module in (
        "dev-dotnet",
        "dev-go",
        "dev-java",
        "dev-javascript",
        "dev-python",
        "dev-paths",
        "dev-nix-ld",
    ):
        assert f"m.nixos.{module}" not in apollo


def test_apollo_includes_frequent_control_tools_only() -> None:
    apollo = read("modules/hosts/apollo/default.nix")

    assert "pkgs.stern" in apollo
    assert "pkgs.nvd" in apollo
    assert "pkgs.bpftrace" not in apollo


def test_apollo_allows_only_local_tcp_forwarding() -> None:
    apollo = read("modules/hosts/apollo/default.nix")

    assert 'AllowTcpForwarding = lib.mkForce "local";' in apollo
    assert 'GatewayPorts = "no";' in apollo


def test_apollo_diagnosis_checks_every_daily_health_boundary_without_secrets() -> None:
    diagnosis = recipe("diagnose-apollo-worklab")

    for required in (
        "df -h /",
        "free -h",
        "systemctl --failed",
        'test -z "$failed"',
        "alloy.service",
        "syncthing.service",
        "microvms.target",
        "herdr-session-homelab.service",
        "herdr-session-dataplatform.service",
        "http://orion:5000/nix-cache-info",
        "ready=$(ssh -n",
        "status.conditions",
        'test "$ready" -eq 5',
    ):
        assert required in diagnosis
    for forbidden in ("k3s-cluster/token", "k3s.yaml", ".kube/config", "set -x"):
        assert forbidden not in diagnosis


def test_apollo_kubeconfig_merges_without_replacing_existing_context(
    tmp_path: Path,
) -> None:
    current = tmp_path / "config"
    current.write_text(
        """apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://kept.example
  name: kept
contexts:
- context:
    cluster: kept
    user: kept
  name: kept
current-context: kept
users:
- name: kept
  user:
    token: kept
"""
    )
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    ssh = fake_bin / "ssh"
    ssh.write_text(
        """#!/bin/sh
cat <<'EOF'
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://127.0.0.1:6443
  name: default
contexts:
- context:
    cluster: default
    user: default
  name: default
current-context: default
users:
- name: default
  user:
    token: apollo
EOF
"""
    )
    ssh.chmod(0o755)
    env = os.environ | {
        "HOME": str(tmp_path),
        "KUBECONFIG": str(current),
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
    }

    subprocess.run(
        ["just", "apollo-kubeconfig"], cwd=ROOT, env=env, check=True, capture_output=True
    )
    rendered = subprocess.run(
        ["kubectl", "config", "view", "--raw", "-o", "json"],
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )
    config = json.loads(rendered.stdout)
    contexts = [context["name"] for context in config["contexts"]]
    apollo = next(context for context in config["contexts"] if context["name"] == "apollo-dev")
    cluster = next(
        cluster
        for cluster in config["clusters"]
        if cluster["name"] == apollo["context"]["cluster"]
    )

    assert config["current-context"] == "kept"
    assert contexts.count("apollo-dev") == 1
    assert cluster["cluster"]["server"] == "https://apollo:6443"
    assert stat.S_IMODE(current.stat().st_mode) == 0o600

    kubeconfig = recipe("apollo-kubeconfig")
    assert "ssh -J erik@{{ip_apollo}}:2222" in kubeconfig
    assert "ssh -A" not in kubeconfig


def test_apollo_cluster_lifecycle_is_explicit_and_rebuild_is_guarded() -> None:
    start = recipe("apollo-cluster-start")
    stop = recipe("apollo-cluster-stop")
    rebuild = recipe("apollo-cluster-rebuild")

    start_command = start.split("for attempt", 1)[0]
    for unit in (
        "microvms.target",
        "microvm@cp-1.service",
        "microvm@cp-2.service",
        "microvm@cp-3.service",
        "microvm@w-1.service",
        "microvm@w-2.service",
    ):
        assert unit in start_command
    assert "just diagnose-apollo-worklab" in start
    stop_command = stop.split("states=", 1)[0]
    for unit in (
        "microvms.target",
        "microvm@cp-1.service",
        "microvm@cp-2.service",
        "microvm@cp-3.service",
        "microvm@w-1.service",
        "microvm@w-2.service",
    ):
        assert unit in stop_command
    assert 'grep -c "^inactive$"' in stop
    assert 'test {{quote(confirmation)}} = "REBUILD-APOLLO-CLUSTER"' in rebuild
    assert "just diagnose-apollo-worklab" in rebuild
    assert "just apollo-cluster-stop" in rebuild
    assert "just apollo-cluster-start" in rebuild
    assert "names=(cp-1 cp-2 cp-3 w-1 w-2)" in rebuild
    assert rebuild.index('test -d "$state_dir/$name"') < rebuild.index("rm -rf")
    assert 'rm -rf --one-file-system -- "$state_dir/$name"' in rebuild
    assert "apollo-cluster-rebuild" not in recipe("diagnose-apollo-worklab")


def test_apollo_publishes_atomic_freshness_aware_cluster_readiness() -> None:
    cluster = read("modules/hosts/apollo/k3s-cluster.nix")

    assert 'source = "/var/lib/node-exporter-textfile";' in cluster
    assert 'lib.optional (name == "cp-1")' in cluster
    assert "apollo_k3s_ready_nodes" in cluster
    assert "apollo_k3s_probe_last_success_seconds" in cluster
    assert "status.conditions" in cluster
    assert "mktemp" in cluster
    assert 'mv "$tmp" /host-textfile/apollo-k3s.prom' in cluster
    assert 'OnUnitActiveSec = "1m";' in cluster


def test_apollo_project_environment_gate_runs_inside_each_owned_repository() -> None:
    gate = recipe("verify-apollo-project-environments")

    for project in (
        "dataplatform-spark",
        "dataplatform-airflow",
        "dataplatform-datacontracts",
    ):
        assert project in gate
    assert 'test -d "$repo/.git"' in gate
    assert '(cd "$repo" && devenv test)' in gate
    assert gate.index("${repo##*/}") < gate.index('test -d "$repo/.git"')
    assert "set -x" not in gate


def test_apollo_repository_bootstrap_clones_git_history_without_agent_forwarding() -> None:
    bootstrap = recipe("bootstrap-apollo-worklab-repositories")

    for project in (
        "homelab",
        "dataplatform",
        "dataplatform-spark",
        "dataplatform-airflow",
        "dataplatform-datacontracts",
    ):
        assert project in bootstrap
    assert "bundle create" in bootstrap
    assert "bundle list-heads" in bootstrap
    assert "scp -P 2222" in bootstrap
    assert 'git clone "$bundle" "$target"' in bootstrap
    assert 'git -C "$target" remote set-url origin "$origin"' in bootstrap
    assert "dataplatform-datacontracts/devenv.nix" in bootstrap
    assert 'cmp -s "$root/../../nstech/dataplatform-datacontracts/devenv.nix"' in bootstrap
    assert "dataplatform-datacontracts/.devenv/state/contract-cli" in bootstrap
    assert '"$local_cli/contract-cli" "$local_cli/.version"' in bootstrap
    assert 'chmod 0755 "$HOME/$remote_cli/contract-cli"' in bootstrap
    assert "dataplatform-airflow/devenv.nix" in bootstrap
    assert "dataplatform-airflow/devenv.lock" in bootstrap
    assert 'cp -n .env.example .env' in bootstrap
    assert "ssh -A" not in bootstrap
    subprocess.run(
        ["bash", "-n"], input=textwrap.dedent(bootstrap), text=True, check=True
    )


def test_apollo_owns_the_persistent_worklab_home() -> None:
    apollo = read("modules/hosts/apollo/default.nix")

    for module in (
        "atuin",
        "claude-code",
        "codex",
        "tuicr",
        "opencode",
        "vscode",
        "nvim",
        "hermes-agent",
        "herdr",
        "herdr-worklab",
        "grafatui",
        "tmux",
    ):
        assert f"m.home.{module}" in apollo
    assert "linger = true;" in apollo


def test_worklab_sessions_are_generic_and_safe_by_default() -> None:
    worklab = read("modules/dev/herdr-worklab.nix")

    assert "flake.modules.home.herdr-worklab" in worklab
    assert 'defaultSessions = ["homelab" "dataplatform"]' in worklab
    for project in (
        "dataplatform-spark",
        "dataplatform-airflow",
        "dataplatform-datacontracts",
    ):
        assert project in worklab
    assert 'command = "codex";' in worklab
    assert "--yolo" not in worklab


def test_apollo_uses_passwordless_sudo_and_noninteractive_deploy() -> None:
    apollo = read("modules/hosts/apollo/default.nix")
    deploy = read("modules/deploy-rs.nix")

    assert "security.sudo.wheelNeedsPassword = lib.mkForce false;" in apollo
    assert """apollo = mkNode {
      host = "apollo";
      magicRollback = true;
    };""" in deploy


def test_apollo_agent_defaults_do_not_bypass_approval() -> None:
    apollo = read("modules/hosts/apollo/default.nix")

    for shell in ("bash", "zsh"):
        assert f"programs.{shell}.shellAliases" in apollo
    for command in (
        "--dangerously-skip-permissions",
        "--dangerously-bypass-approvals-and-sandbox",
        "--yolo",
        "--auto",
    ):
        assert command not in apollo


def test_apollo_syncthing_starts_without_peers_or_folders() -> None:
    apollo = read("modules/hosts/apollo/default.nix")
    topology = read("modules/services/syncthing-fleet.nix")

    assert "m.nixos.apollo-syncthing" in apollo
    assert """apollo = {
      devices = [];
      folderPaths = {};
    };""" in topology


def test_gemini_uses_the_host_neutral_worklab_module() -> None:
    gemini = read("modules/hosts/orion/gemini.nix")

    assert "m.home.herdr-worklab" in gemini
    assert "m.home.herdr-gemini" not in gemini
