"""Isolated future FIM host-directory proof; no standing agent or manager access."""
import hashlib
import json
import os
import re
import socket
import subprocess
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).parents[2]
ENGINE = os.environ.get('WAZUH_CONTAINER_ENGINE', 'podman')
IMAGE = re.search(r'image = "([^"]+wazuh-agent[^"]+)"',
                  (ROOT / 'modules/hosts/orion/wazuh-agent.nix').read_text())[1]


def test_host_mutation_restore_without_control_or_content(tmp_path):
    watched = tmp_path / 'watched'
    watched.mkdir()
    control = tmp_path / 'control'
    control.mkdir()
    marker = watched / 'sshd_config.fixture'
    original = 'synthetic-original-never-an-actual-ssh-config\n'
    changed = 'synthetic-changed-private-content-not-an-alert\n'
    marker.write_text(original)
    queue = tmp_path / 'queue'
    queue.mkdir()
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    listener.bind(str(queue / 'queue'))
    listener.settimeout(0.2)
    name = 'wazuh-s07-' + uuid.uuid4().hex
    records = []

    def collect_until(predicate, timeout=12):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                record = listener.recv(65536).decode().rstrip('\0')
                records.append(record)
                assert len(records) <= 64, 'unexpected event flood in one-file fixture'
                if predicate(record):
                    return
            except TimeoutError:
                pass
        assert False, f'expected FIM event missing; {len(records)} records received'

    def event(record, kind):
        start = record.find('{')
        if start < 0:
            return False
        try:
            data = json.loads(record[start:]).get('data', {})
        except json.JSONDecodeError:
            return False
        return data.get('path') == '/host-fim/sshd_config.fixture' and data.get('type') == kind

    command = [ENGINE, 'run', '-d', '--rm', '--pull=never', '--name', name,
               '--network=none', '--memory=256m', '--cpus=1',
               '--volume', f'{watched}:/host-fim:ro',
               '--volume', f'{queue}:/var/ossec/queue/sockets',
               '--volume', f'{ROOT / "tests/wazuh-agent-canary/fixtures/fim-canary.xml"}:/var/ossec/etc/ossec.conf:ro',
               '--entrypoint', '/var/ossec/bin/wazuh-syscheckd', IMAGE,
               '-f']
    try:
        subprocess.run(command, capture_output=True, check=True, timeout=15)
        collect_until(lambda record: 'scan_end' in record)
        marker.write_text(changed)
        (control / 'outside.fixture').write_text(changed)
        collect_until(lambda record: event(record, 'modified'))
        marker.write_text(original)
        collect_until(lambda record: event(record, 'modified'))
        # Observe a short quiet period so queued duplicates/control events count.
        deadline = time.monotonic() + 1
        while time.monotonic() < deadline:
            try:
                records.append(listener.recv(65536).decode().rstrip('\0'))
                assert len(records) <= 64, 'unexpected event flood in one-file fixture'
            except TimeoutError:
                pass
        assert marker.read_text() == original
        serialized = '\n'.join(records)
        assert changed.strip() not in serialized
        assert original.strip() not in serialized
        assert 'outside.fixture' not in serialized
        assert 'rootcheck:' not in serialized
        changes = [record for record in records if event(record, 'modified')]
        assert len(changes) == 2
        events = [json.loads(record[record.find('{'):])['data'] for record in changes]
        assert [event['attributes']['hash_sha256'] for event in events] == [
            hashlib.sha256(content.encode()).hexdigest() for content in (changed, original)]
        assert all('diff' not in event for event in events)
        readonly = subprocess.run([ENGINE, 'exec', name, '/bin/sh', '-c',
                                   'echo forbidden > /host-fim/write-probe'],
                                  capture_output=True, text=True, timeout=5)
        assert readonly.returncode != 0, 'host directory mount allowed container writes'
        # A dead container or a missing shell is also nonzero; require the
        # kernel's read-only refusal so the fixture proves isolation.
        assert 'read-only file system' in (readonly.stderr or '').lower(), (
            f'write probe failed for another reason: {readonly.stderr!r}')
        assert not (watched / 'write-probe').exists()
    finally:
        subprocess.run([ENGINE, 'rm', '-f', name], capture_output=True, timeout=10)
        listener.close()
