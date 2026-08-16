from pathlib import Path


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
    assert "/home/erik/homelab-iac" not in (Path(__file__).parents[2] / "justfile").read_text()


def test_drift_path_keeps_git_for_terragrunt_repo_root():
    module = (
        Path(__file__).parents[2] / "modules/services/homelab-iac-drift.nix"
    ).read_text()

    assert "\n          git\n" in module
