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
    revision = "9065d0aab9227b6a4eed88200633dd3dc883fd18"
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



def test_whole_service_result_and_recovery(tmp_path):
    import importlib.util
    helper = ROOT / 'modules/services/_homelab-iac-drift-report.py'
    assert helper.exists(), 'whole-service reporter missing'
    spec = importlib.util.spec_from_file_location('drift_report', helper)
    report = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(report)
    cfg = dict(state_dir=tmp_path / 'private', metrics_dir=tmp_path / 'metrics',
               result_file=tmp_path / 'result.json', instance='discovery',
               revision='a'*40, scope='b'*64)
    def event(action, now, invocation, service='success', status=0, result=None):
        if action == 'finish' and result is not None:
            cfg['result_file'].write_text(json.dumps(dict(schemaVersion=1, sourceRevision=cfg['revision'], scopeSha256=cfg['scope'], **result)))
        return report.update(cfg, action, now=now, invocation=invocation,
                             service_result=service, exit_status=str(status), exit_code='exited')
    event('restore', 90, '')
    assert 'homelab_iac_drift_outcome{instance="discovery"} 0' in (cfg['metrics_dir']/'drift.prom').read_text()
    for index, (service, status, result, outcome, notice) in enumerate([
        ('exit-code',1,None,4,4), # bootstrap before script result
        ('exit-code',75,None,6,4), # shared apply lock timeout
        ('timeout',15,None,5,4),
        ('signal',9,None,4,4),
        ('success',0,dict(outcome='clean',notification='not-required'),2,0),
        ('success',2,dict(outcome='drift',notification='delivered'),3,1),
        ('success',2,dict(outcome='drift',notification='failed'),3,2),
        ('exit-code',1,dict(outcome='error',notification='failed'),4,2),
        ('success',0,None,4,4), # no structured result cannot look clean
    ]):
        start=100+index*10
        previous=event('begin',start,str(index))
        assert not cfg['result_file'].exists(), 'old result must not survive begin'
        value=event('finish',start+2,str(index),service,status,result)
        assert value['outcome']==outcome
        assert value['notification']==notice
        assert value['duration_seconds']==2
        assert value['lock_contention']==int(outcome==6)
        assert value['last_complete_seconds']==(start+2 if outcome in (2,3) else previous['last_complete_seconds'])
    assert (cfg['state_dir']/'state.json').stat().st_mode & 0o777 == 0o600
    assert (cfg['metrics_dir']/'drift.prom').stat().st_mode & 0o777 == 0o644


def test_result_identity_and_file_boundary_fail_closed(tmp_path):
    import importlib.util
    helper = ROOT / 'modules/services/_homelab-iac-drift-report.py'
    spec = importlib.util.spec_from_file_location('drift_report', helper)
    report = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(report)
    cfg = dict(state_dir=tmp_path/'private', metrics_dir=tmp_path/'metrics',
               result_file=tmp_path/'result.json', instance='discovery', revision='a'*40, scope='b'*64)
    for index, bad in enumerate(('scope', 'symlink', 'too-large', 'oom')):
        report.update(cfg,'begin',now=100+index*10,invocation=bad)
        data=dict(schemaVersion=1,sourceRevision=cfg['revision'],scopeSha256=cfg['scope'],outcome='clean',notification='not-required')
        if bad=='scope': data['scopeSha256']='c'*64
        if bad=='symlink':
            target=tmp_path/'private-file'
            target.write_text(json.dumps(data))
            cfg['result_file'].symlink_to(target)
        else:
            cfg['result_file'].write_text('x'*5000 if bad=='too-large' else json.dumps(data))
        result=report.update(cfg,'finish',now=102+index*10,invocation=bad,
                             service_result='oom-kill' if bad=='oom' else 'success',exit_code='exited',exit_status='0')
        assert result['outcome']==4
        assert result['last_complete_seconds']==0


def test_growing_result_is_bounded_after_open(tmp_path, monkeypatch):
    import importlib.util
    import os
    helper = ROOT / 'modules/services/_homelab-iac-drift-report.py'
    spec = importlib.util.spec_from_file_location('drift_report', helper)
    report = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(report)
    cfg = dict(state_dir=tmp_path/'private',metrics_dir=tmp_path/'metrics',result_file=tmp_path/'result.json',
               instance='discovery',revision='a'*40,scope='b'*64)
    report.update(cfg,'begin',now=100,invocation='fixture')
    cfg['result_file'].write_text(json.dumps(dict(schemaVersion=1,sourceRevision='a'*40,scopeSha256='b'*64,outcome='clean',notification='not-required')))
    fstat = os.fstat
    def growing(fd):
        result = fstat(fd)
        with cfg['result_file'].open('a') as stream:
            stream.write(' '*10000)
        return result
    monkeypatch.setattr(report.os,'fstat',growing)
    state=report.update(cfg,'finish',now=102,invocation='fixture',service_result='success',exit_code='exited',exit_status='0')
    assert state['outcome']==4
    assert state['last_complete_seconds']==0


def test_finish_without_matching_begin_rejects_previous_clean_result(tmp_path):
    import importlib.util
    spec = importlib.util.spec_from_file_location('drift_report', ROOT/'modules/services/_homelab-iac-drift-report.py')
    report = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(report)
    cfg = dict(state_dir=tmp_path/'private', metrics_dir=tmp_path/'metrics',
               result_file=tmp_path/'result.json', instance='discovery', revision='a'*40, scope='b'*64)
    report.update(cfg, 'begin', now=100, invocation='previous')
    cfg['result_file'].write_text(json.dumps(dict(schemaVersion=1, sourceRevision=cfg['revision'], scopeSha256=cfg['scope'], outcome='clean', notification='not-required')))
    report.update(cfg, 'finish', now=101, invocation='previous', service_result='success', exit_status='0', exit_code='exited')
    value = report.update(cfg, 'finish', now=102, invocation='new-without-begin', service_result='success', exit_status='0', exit_code='exited')
    assert value['outcome'] == 4
    assert value['last_complete_seconds'] == 101
