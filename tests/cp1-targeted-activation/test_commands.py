"""Exercise the actual guest shell against disposable command fixtures."""
import os
from pathlib import Path
import subprocess

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/activate-cp1.sh'
GUEST = SCRIPT.read_text().split("<<'GUEST'\n", 1)[1].split('\nGUEST\n', 1)[0]


def executable(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('#!/usr/bin/env bash\nset -eu\n' + text)
    path.chmod(0o755)


def fixture(tmp_path, *, failure=False, active=False, wrong_host=False, retained_pid=False, no_k3s=False, signal=False, start_failure=False, stale_closure=False, stale_exec=False):
    commands = tmp_path / 'commands'; commands.mkdir()
    old, new, nix = (tmp_path / name for name in ('old', 'new', 'nix'))
    log = tmp_path / 'calls'; log.touch()
    current = tmp_path / 'current'; current.write_text(str(old))
    env = dict(os.environ, PATH=str(commands)+':'+os.environ['PATH'], LOG=str(log),
               CURRENT=str(current), NEW=str(new), OLD=str(old),
               FAIL='1' if failure else '0', ACTIVE='1' if active else '0', PID='42' if retained_pid else '0', NO_K3S='1' if no_k3s else '0', SIGNAL='1' if signal else '0', START_FAIL='1' if start_failure else '0', STALE_CLOSURE='1' if stale_closure else '0', STALE_EXEC='1' if stale_exec else '0')
    executable(commands/'hostname', 'echo '+('other' if wrong_host else 'cp-1'))
    executable(commands/'readlink', 'cat "$CURRENT"')
    executable(commands/'systemctl', '''
printf 'systemctl %s\\n' "$*" >> "$LOG"
case "$1" in
 is-enabled) echo enabled;;
 is-active)
 if [ "$ACTIVE" = 1 ] || { [ "$2" = k3s.service ] && [ "$(cat "$CURRENT")" = "$NEW" ] && [ "$NO_K3S" = 0 ]; }; then echo active; else echo inactive; exit 3; fi;;
 show) case "$*" in *MainPID*) echo "$PID";; *Restart*) echo no;; *ExecStart*) if [ "$STALE_EXEC" = 1 ]; then echo "k3s server --cluster-init"; else echo "k3s server --server https://10.250.0.13:6443"; fi;; *) echo masked;; esac;;
 start) [ "$START_FAIL" = 0 ] || exit 43;;
 stop) exit 0;;
 *) exit 90;;
esac
''')
    executable(commands/'timeout', 'printf "timeout %s\\n" "$1" >> "$LOG"; shift; exec "$@"')
    executable(new/'bin/switch-to-configuration', '''
echo "switch $1" >> "$LOG"
if [ "$1" = switch ]; then
 [ "$SIGNAL" = 0 ] || kill -TERM "$PPID"
 [ "$FAIL" = 0 ] || exit 42
 [ "$STALE_CLOSURE" = 1 ] || printf '%s' "$NEW" > "$CURRENT"
fi
''')
    executable(nix/'bin/nix-store', 'echo "nix-store $*" >> "$LOG"; cat >/dev/null')
    executable(nix/'bin/nix-env', 'echo "nix-env $*" >> "$LOG"')
    registration = tmp_path/'registration'; registration.write_text('fixture')
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    return env, [str(old),str(new),str(old),boot,str(nix),str(registration),"enabled","enabled"], log


def run(tmp_path, mode='activate', **kwargs):
    env,args,log = fixture(tmp_path, **kwargs)
    result = subprocess.run(['bash','-se','--',mode,*args], input=GUEST, text=True,
                            env=env,capture_output=True,timeout=5)
    return result, log.read_text()


def test_preview_cannot_set_profile_or_switch(tmp_path):
    result,calls = run(tmp_path, 'preview')
    assert result.returncode == 0
    assert 'switch dry-activate' in calls
    assert 'nix-env' not in calls and 'switch switch' not in calls


@pytest.mark.parametrize('option', ['active', 'wrong_host', 'retained_pid'])
def test_wrong_identity_or_active_recovery_unit_aborts(tmp_path,option):
    result,calls = run(tmp_path, **{option: True})
    assert result.returncode != 0
    assert 'switch ' not in calls and 'nix-env' not in calls


def test_failed_switch_stops_exact_units_without_rollback(tmp_path):
    result,calls = run(tmp_path,failure=True)
    assert result.returncode == 42
    assert 'systemctl stop k3s.service k3s-bootstrap-secrets.timer k3s-bootstrap-secrets.service k3s-manifest-reconcile.service' in calls
    assert 'rollback' not in calls and 'restart' not in calls and 'microvm' not in calls
    assert calls.count('switch switch') == 1


def test_activation_budget_covers_reviewed_five_minute_start(tmp_path):
    result,calls = run(tmp_path)
    assert result.returncode == 0
    budget = max(int(line.split()[1]) for line in calls.splitlines() if line.startswith('timeout '))
    assert 300 <= budget <= 360


def test_term_attempts_bounded_stop(tmp_path):
    result,calls = run(tmp_path,signal=True)
    assert result.returncode == 143
    assert 'systemctl stop k3s.service k3s-bootstrap-secrets.timer k3s-bootstrap-secrets.service k3s-manifest-reconcile.service' in calls


def test_successful_switch_without_k3s_is_not_success(tmp_path):
    result,calls = run(tmp_path,no_k3s=True)
    assert result.returncode != 0
    assert 'systemctl stop k3s.service' in calls


@pytest.mark.parametrize(('observed','expected','accepted'), [
    ('absent','absent',True), ('existing','existing',True),
    ('existing','absent',False), ('dangling','absent',False),
    ('absent','existing',False), ('dangling','existing',False),
])
def test_guest_profile_absence_is_explicit(tmp_path, observed, expected, accepted):
    target=tmp_path/'target';target.mkdir()
    profile=tmp_path/'profile'
    if observed != 'absent':
        profile.symlink_to(target if observed == 'existing' else tmp_path/'missing')
    guard=GUEST.split('[[ $(readlink -e /run/current-system) == "$old" ]]\n',1)[1].split('[[ $(timeout 10 systemctl is-enabled',1)[0]
    guard=guard.replace('/nix/var/nix/profiles/system',str(profile))
    result=subprocess.run(['bash','-se'],input=guard,text=True,
        env=dict(os.environ,profile='absent' if expected=='absent' else str(target)),capture_output=True)
    assert (result.returncode == 0) == accepted


def test_single_explicit_start_follows_switch(tmp_path):
    result,calls=run(tmp_path)
    assert result.returncode == 0
    assert calls.count('systemctl start k3s.service') == 1
    assert calls.index('switch switch') < calls.index('systemctl start k3s.service')

def test_explicit_start_failure_stops_without_retry(tmp_path):
    result,calls=run(tmp_path,start_failure=True)
    assert result.returncode == 43
    assert calls.count('systemctl start k3s.service') == 1
    assert 'systemctl stop k3s.service' in calls


@pytest.mark.parametrize('option',['stale_closure','stale_exec'])
def test_unexpected_loaded_configuration_never_starts(tmp_path,option):
    result,calls=run(tmp_path,**{option:True})
    assert result.returncode != 0
    assert 'systemctl start k3s.service' not in calls
    assert 'systemctl stop k3s.service' in calls
