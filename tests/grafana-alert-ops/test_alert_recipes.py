import pathlib


ROOT = pathlib.Path(__file__).resolve().parents[2]


def test_endeavour_upgrade_has_diagnostics_and_retry_target():
    justfile = (ROOT / "justfile").read_text()
    assert "diagnose endeavour nixos-upgrade.service" in justfile
    assert (
        "endeavour-upgrade) host=endeavour; "
        "unit=nixos-upgrade.service; action=reset ;;"
    ) in justfile


def test_kepler_upgrade_has_read_only_diagnostics():
    justfile = (ROOT / "justfile").read_text()
    assert "diagnose kepler nixos-upgrade.service" in justfile
    assert (
        "kepler-upgrade) host=kepler; "
        "unit=nixos-upgrade.service; action=reset ;;"
    ) in justfile


def test_failed_unit_diagnostics_cannot_hang_after_ssh_connects():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("grafana-alert-diagnostics:", 1)[1].split("\n# ", 1)[0]

    assert "-o ServerAliveInterval=3" in recipe
    assert "-o ServerAliveCountMax=1" in recipe


def test_kepler_kernel_diagnostics_are_bounded_and_read_only():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("diagnose-kepler-kernel:", 1)[1].split("\n# ", 1)[0]

    for value in (
        'up{instance="kepler",job="integrations/unix"}',
        '{host="kepler"}',
        "reboot is needed",
        "reboot_required=1",
        "--max-time 8",
        "ServerAliveCountMax=1",
    ):
        assert value in recipe
    assert "systemctl restart" not in recipe
    assert "sudo reboot" not in recipe


def test_transient_discovery_jobs_have_bounded_retries():
    wiki = (ROOT / "modules/hosts/discovery/hermes-wiki.nix").read_text()
    restic = (ROOT / "modules/services/restic-tofu-state.nix").read_text()

    seed = wiki.split("systemd.services.hermes-wiki-cron-seed", 1)[1]
    assert 'Restart = "on-failure";' in seed
    assert 'RestartSec = "30s";' in seed
    assert 'ready=0' in wiki
    assert '[ "$ready" -eq 1 ]' in wiki

    offsite = restic.split(
        "systemd.services.restic-backups-tofu-state-offsite", 1
    )[1]
    assert 'Restart = "on-failure";' in offsite
    assert 'RestartSec = "60s";' in offsite


def test_telstar_lock_failure_is_not_automatically_restarted():
    module = (ROOT / "modules/hosts/discovery/telstar-capture.nix").read_text()
    assert "RestartPreventExitStatus = [75];" in module


def test_telstar_lock_recovery_is_exact_and_guarded():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("recover-discovery-telstar-lock lock_id:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "pause-discovery-telstar" in recipe
    assert "bash oracle/bin/telstar-lock-recover.sh" in recipe
    assert "{{lock_id}}" in recipe
    assert "systemctl start telstar-capture.service" in recipe


def test_airflow_pull_robot_delegates_to_servarr_without_printing_secrets():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("provision-airflow-harbor-pull-robot:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "vault_root_token" in recipe
    assert "just provision-airflow-harbor-pull-robot" in recipe
    assert "set -x" not in recipe
