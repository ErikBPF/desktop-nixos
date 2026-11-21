"""Bounded private lifecycle state and atomic gauges for the systemd drift unit."""
import argparse
import fcntl
import json
import math
import os
from pathlib import Path
import re
import stat
import tempfile
import time

FIELDS = ('last_attempt_seconds', 'last_complete_seconds', 'last_publish_seconds',
          'duration_seconds', 'outcome', 'notification', 'lock_contention')
OUTCOMES = {'clean': 2, 'drift': 3, 'error': 4}
NOTIFICATIONS = {'not-required': 0, 'delivered': 1, 'failed': 2, 'not-configured': 3}


def atomic(path, value, mode):
    fd, name = tempfile.mkstemp(prefix='.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(value)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
        fd = os.open(path.parent, os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def update(cfg, action, *, now=None, invocation='', service_result='', exit_status='', exit_code=''):
    now = time.time() if now is None else now
    if action not in ('begin', 'finish', 'restore') or not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9.-]*', cfg['instance']):
        raise ValueError('invalid lifecycle action or identity')
    if type(now) not in (int, float) or not math.isfinite(now) or not 0 <= now <= time.time():
        raise ValueError('invalid lifecycle time')
    private, metrics = Path(cfg['state_dir']), Path(cfg['metrics_dir'])
    private.mkdir(mode=0o700, parents=True, exist_ok=True)
    metrics.mkdir(mode=0o755, parents=True, exist_ok=True)
    path = private / 'state.json'
    with (private / 'state.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = dict.fromkeys(FIELDS, 0)
        state['invocation'] = ''
        if path.exists():
            state = json.loads(path.read_text())
            if any(type(state.get(k)) not in (int, float) or not math.isfinite(state[k]) or state[k] < 0 for k in FIELDS):
                raise ValueError('invalid persisted lifecycle state')
            if state['outcome'] not in range(7) or state['notification'] not in range(5) or state['lock_contention'] not in (0, 1):
                raise ValueError('invalid persisted lifecycle enum')
            if any(state[k] > now for k in FIELDS if k.startswith('last_')):
                raise ValueError('future persisted lifecycle state')
        if action == 'begin' or (action == 'finish' and state['invocation'] != invocation):
            state.update(last_attempt_seconds=now, duration_seconds=0, outcome=1,
                         notification=4, lock_contention=0, invocation=invocation)
            if action == 'begin':
                Path(cfg['result_file']).unlink(missing_ok=True)
        if action == 'finish':
            state.update(duration_seconds=max(0, now-state['last_attempt_seconds']), outcome=4,
                         notification=4, lock_contention=0)
            if service_result == 'timeout':
                state['outcome'] = 5
            elif exit_code == 'exited' and exit_status == '75':
                state.update(outcome=6, lock_contention=1)
            elif service_result in ('success', 'exit-code') and exit_code == 'exited' and exit_status in ('0', '1', '2'):
                try:
                    result_path = Path(cfg['result_file'])
                    fd = os.open(result_path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
                    with os.fdopen(fd, 'rb') as stream:
                        info = os.fstat(stream.fileno())
                        if not stat.S_ISREG(info.st_mode) or info.st_size > 4096:
                            raise ValueError('invalid result file')
                        content = stream.read(4097)
                        if len(content) > 4096:
                            raise ValueError('result grew beyond its bound')
                        result = json.loads(content)
                    if (set(result) != {'schemaVersion', 'sourceRevision', 'scopeSha256', 'outcome', 'notification'}
                            or type(result['schemaVersion']) is not int or result['schemaVersion'] != 1 or result['sourceRevision'] != cfg['revision']
                            or result['scopeSha256'] != cfg['scope']
                            or result['outcome'] != {'0': 'clean', '1': 'error', '2': 'drift'}[exit_status]
                            or result['notification'] not in NOTIFICATIONS
                            or (result['outcome'] == 'clean') != (result['notification'] == 'not-required')):
                        raise ValueError('incompatible result')
                    state.update(outcome=OUTCOMES[result['outcome']], notification=NOTIFICATIONS[result['notification']])
                    if state['outcome'] in (2, 3):
                        state['last_complete_seconds'] = now
                except (OSError, ValueError, TypeError):
                    pass
        state.update(last_publish_seconds=now, sourceRevision=cfg['revision'], scopeSha256=cfg['scope'])
        atomic(path, json.dumps(state)+'\n', 0o600)
        if action == 'finish':
            atomic(private/'last-result.json', json.dumps(state)+'\n', 0o600)
        labels = 'instance="'+cfg['instance']+'"'
        text = ''.join(f'homelab_iac_drift_{k}{{{labels}}} {state[k]}\n' for k in FIELDS)
        atomic(metrics/'drift.prom', text, 0o644)
        return state


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('begin', 'finish', 'restore'))
    for name in ('state-dir', 'metrics-dir', 'result-file', 'instance', 'revision', 'scope'):
        parser.add_argument('--'+name, required=True)
    args = vars(parser.parse_args())
    action = args.pop('action')
    update(args, action, invocation=os.environ.get('INVOCATION_ID', ''),
           service_result=os.environ.get('SERVICE_RESULT', ''),
           exit_status=os.environ.get('EXIT_STATUS', ''), exit_code=os.environ.get('EXIT_CODE', ''))
