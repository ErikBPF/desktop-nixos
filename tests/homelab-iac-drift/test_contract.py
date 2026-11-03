import json
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).parents[2]


def test_drift_exit_is_not_a_failed_unit():
    module = (
        Path(__file__).parents[2] / "modules/services/homelab-iac-drift.nix"
    ).read_text()

    assert 'SuccessExitStatus = [2];' in module


def test_github_app_token_is_refreshed_at_runtime():
    module = (
        Path(__file__).parents[2] / "modules/services/homelab-iac-drift.nix"
    ).read_text()

    assert "githubAppManagementEnvFile" in module
    assert "refresh-github-app-token.sh" in module
    assert "GITHUB_APP_MANAGEMENT_REFRESH_TOKEN=" in module
    assert "bao kv get -field=GITHUB_APP_MANAGEMENT_REFRESH_TOKEN" in module
    assert 'GITHUB_APP_MANAGEMENT_TOKEN="$(bash bin/refresh-github-app-token.sh)"' in module


def test_drift_executes_the_pinned_iac_artifact_without_git():
    module = (
        Path(__file__).parents[2] / "modules/services/homelab-iac-drift.nix"
    ).read_text()

    assert "inputs.homelab-iac" in module
    assert 'StateDirectory = "homelab-iac-drift";' in module
    assert 'StateDirectoryMode = "0700";' in module
    assert 'cd "$STATE_DIRECTORY/source"' in module
    assert "cp -R --no-preserve=mode" in module
    assert "set -euo pipefail" in module
    assert "git pull" not in module
    assert "repoPath" not in module
    assert "/home/erik/homelab-iac" not in ("\n".join(p.read_text() for p in [ROOT / "justfile", *sorted((ROOT / "just").glob("*.just"))]))


def test_pinned_iac_revision_matches_published_discovery_guard():
    root = Path(__file__).parents[2]
    flake = (root / "flake.nix").read_text()
    revision = "19a6def2a8f4673b11b971ab2b3feae661eab5ca"
    pin = re.search(r"homelab-iac\s*=\s*\{([^}]+)\};", flake)

    assert pin is not None
    assert f'url = "github:ErikBPF/homelab-iac/{revision}";' in pin.group(1)
    assert "flake = false;" in pin.group(1)
    lock = json.loads((root / "flake.lock").read_text())
    node = lock["nodes"][lock["nodes"][lock["root"]]["inputs"]["homelab-iac"]]
    assert node["original"]["rev"] == revision
    assert node["locked"]["rev"] == revision
    assert node["flake"] is False


def test_drift_path_keeps_git_for_terragrunt_repo_root():
    module = (
        Path(__file__).parents[2] / "modules/services/homelab-iac-drift.nix"
    ).read_text()

    assert re.search(r"\n\s+git\n", module)
    # bin/drift-check.sh and bin/iac-apply.sh build their summaries with awk;
    # `path` replaces PATH, so the unit must ship it.
    assert re.search(r"\n\s+gawk\n", module)


def test_merged_main_apply_is_opt_in_and_evaluates_the_merged_revision():
    module = (
        Path(__file__).parents[2] / "modules/services/homelab-iac-drift.nix"
    ).read_text()

    assert "applyMergedMain = lib.mkEnableOption" in module
    assert "OnUnitActiveSec = cfg.mainPollInterval;" in module

    service = module.split("systemd.services.homelab-iac-main-apply", 1)[1]
    assert "https://github.com/ErikBPF/homelab-iac" in service
    assert "bin/iac-apply.sh" in service
    assert "applied-sha" in service
    assert "refused-sha" in service


def test_merged_main_apply_is_guarded_and_has_no_remote_trigger():
    module = (
        Path(__file__).parents[2] / "modules/services/homelab-iac-drift.nix"
    ).read_text()

    service = module.split("systemd.services.homelab-iac-main-apply", 1)[1].split(
        "systemd.timers.homelab-iac-main-apply", 1
    )[0]
    assert "systemctl start" not in service
    assert "curl" not in service.split("serviceConfig", 1)[1]
    assert 'CacheDirectory = "homelab-iac-tf-plugin-cache";' in service
    assert 'flock -w 900 -E 75 "$CACHE_DIRECTORY/run.lock"' in service
    assert "75)" in service, "a busy lock must retry, not fail the revision"
    assert "failed-sha" in service
    assert "conflicts" not in service
    assert 'TF_PLUGIN_CACHE_DIR = "/var/lib/homelab-iac-drift/plugin-cache"' not in module
    assert 'default = ["tailscale/acl"];' in module
    assert "IAC_APPLY_DENYLIST" in module


def test_discovery_enables_the_merged_main_apply():
    host = (
        Path(__file__).parents[2] / "modules/hosts/discovery/default.nix"
    ).read_text()

    assert "applyMergedMain = true;" in host


def test_apply_attribution_has_awk():
    module = (
        Path(__file__).parents[2] / "modules/services/homelab-iac-drift.nix"
    ).read_text()

    # bin/iac-apply.sh attributes plan lines with awk; without it every changed
    # unit looks unattributed and the applier refuses every revision.
    assert "\n      gawk\n" in module


def test_github_provider_token_is_resolved_from_openbao():
    module = (
        Path(__file__).parents[2] / "modules/services/homelab-iac-drift.nix"
    ).read_text()

    assert "auth/approle/login" in module
    assert "role_id=\"$VAULT_ROLE_ID\" secret_id=\"$VAULT_SECRET_ID\"" in module
    assert "-mount=secret iac/github" in module


def test_pinned_source_gets_local_git_metadata_for_terragrunt():
    module = (
        Path(__file__).parents[2] / "modules/services/homelab-iac-drift.nix"
    ).read_text()

    init = 'git -c init.defaultBranch=main init --quiet "$STATE_DIRECTORY/source"'
    assert init in module
    assert module.index("cp -R --no-preserve=mode") < module.index(init)
    assert module.index(init) < module.index('cd "$STATE_DIRECTORY/source"')

