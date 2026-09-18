from pathlib import Path
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
        "herdr-session-homelab.service",
        "herdr-session-dataplatform.service",
        "http://orion:5000/nix-cache-info",
    ):
        assert required in diagnosis
    for forbidden in (
        "microvms.target",
        "microvm@",
        "ready=$(ssh -n",
        "k3s-cluster/token",
        "k3s.yaml",
        ".kube/config",
        "set -x",
    ):
        assert forbidden not in diagnosis


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


def test_apollo_syncthing_shares_selected_documents_with_orion() -> None:
    topology = read("modules/services/syncthing-fleet.nix")
    apollo = topology.split("    apollo = {", 1)[1].split("\n    };", 1)[0]
    assert 'devices = ["orion"]' in apollo
    assert 'path = "/home/${u}/Documents/"' in apollo
    assert "stignore-apollo-repositories" in apollo
    assert "versioning = stateVersioning" in apollo
    # Syncthing resolves includes relative to Documents, including /nix/store.
    assert "#include ${stignore}" not in topology
    patterns = read("modules/common/stignore-apollo-repositories").splitlines()
    assert patterns[-1] == "*"
    for denied in (
        "**/.env.*", "**/*.secrets.json", "**/worktrees", "**/.local",
        "**/.codex", "**/.terragrunt-cache", "**/.devenv", "**/.storage",
        "**/graphify-out", "**/.env-*",
    ):
        assert patterns.index(denied) < patterns.index("!/erik/homelab")
    assert "!/nstech/dataplatform" in patterns
