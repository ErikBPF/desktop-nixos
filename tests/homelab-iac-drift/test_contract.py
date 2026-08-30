import json
import re
import subprocess
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


def test_pinned_iac_revision_manages_cognee_repo():
    flake = (Path(__file__).parents[2] / "flake.nix").read_text()

    assert "dc54f16afcf4f5b797c676a043903c5729786181" in flake


def test_drift_path_keeps_git_for_terragrunt_repo_root():
    module = (
        Path(__file__).parents[2] / "modules/services/homelab-iac-drift.nix"
    ).read_text()

    assert "\n          git\n" in module


def test_pinned_source_gets_local_git_metadata_for_terragrunt():
    module = (
        Path(__file__).parents[2] / "modules/services/homelab-iac-drift.nix"
    ).read_text()

    init = 'git -c init.defaultBranch=main init --quiet "$STATE_DIRECTORY/source"'
    assert init in module
    assert module.index("cp -R --no-preserve=mode") < module.index(init)
    assert module.index(init) < module.index('cd "$STATE_DIRECTORY/source"')


def test_equivalence_recipe_is_private_sequential_and_action_only():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("p2-iac-plan-equivalence:", 1)[1].split("\n# ", 1)[0]

    assert 'REV="$(jq -r' in recipe
    assert "NAR_HASH" not in recipe
    assert "homelab-iac-drift.timer" in recipe
    assert "homelab-iac-drift.service" in recipe
    assert 'systemctl mask --runtime "$service"' in recipe
    assert 'systemctl unmask --runtime "$service"' in recipe
    assert 'systemctl is-failed --quiet "$service"' in recipe
    assert 'systemctl show -p ActiveState --value "$service"' in recipe
    assert '"$service_state" = inactive' in recipe
    assert recipe.index('systemctl unmask --runtime "$service"') < recipe.index(
        'systemctl start "$timer"'
    )
    assert "umask 077" in recipe
    assert "mktemp -d /run/homelab-iac-p2.XXXXXX" in recipe
    assert 'export DISCORD_WEBHOOK_URL=""' in recipe
    assert 'export PATH="$PATH:/run/current-system/sw/bin"' in recipe
    assert "/run/wrappers/bin/sudo -u erik env -i" in recipe
    assert 'TG_TF_PATH="$TG_TF_PATH"' in recipe
    assert 'TF_PLUGIN_CACHE_DIR="$TF_PLUGIN_CACHE_DIR"' in recipe
    assert 'SOPS_AGE_KEY_FILE="$SOPS_AGE_KEY_FILE"' in recipe
    assert "fetch --quiet --depth=1 origin \"$REV\"" in recipe
    assert "run_plan pinned" in recipe
    assert "run_plan legacy" in recipe
    assert recipe.index("run_plan pinned") < recipe.index("run_plan legacy")
    assert '.resource_changes | resource("resource_changes")' in recipe
    assert '.resource_drift | resource("resource_drift")' in recipe
    assert "output_changes" in recipe
    assert "cmp -s" in recipe
    assert "rm -rf -- \"$scratch\"" in recipe
    assert ".gsd/evidence/p2-iac-plan-equivalence.json" in recipe
    assert "planned_values" not in recipe


def test_equivalence_normalizer_keeps_output_actions_without_values():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    program = re.search(
        r'jq -c --arg unit "\$unit" \'\n(.*?)\n        \' "\$json_dir/\$unit"',
        justfile,
        re.DOTALL,
    )
    assert program is not None
    plan = {
        "output_changes": {
            "endpoint": {
                "actions": ["update"],
                "before": "secret-before",
                "after": "secret-after",
            }
        }
    }

    result = subprocess.run(
        ["jq", "-c", "--arg", "unit", "unit/tfplan.json", program.group(1)],
        input=json.dumps(plan),
        text=True,
        capture_output=True,
        check=True,
    )

    assert json.loads(result.stdout) == {
        "unit": "unit/tfplan.json",
        "scope": "output_changes",
        "name": "endpoint",
        "actions": ["update"],
    }
    assert "secret-before" not in result.stdout
    assert "secret-after" not in result.stdout
