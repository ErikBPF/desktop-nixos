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
