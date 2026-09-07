"""Usage: python test_audit.py evaluated-settings.json /nix/store/.../bin/bao."""
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error

settings = json.loads(Path(sys.argv[1]).read_text())
audit = settings.get('audit', [])
assert len(audit) == 1, 'exactly one declarative audit device required'
assert settings.get('unsafe_allow_api_audit_creation') is False
options = audit[0]['file']['host-file']['options']
assert options == {'file_path':'/var/log/openbao/audit.json','mode':'0600','log_raw':'false','hmac_accessor':'true'}
with tempfile.TemporaryDirectory(prefix='bao-audit-test-') as directory:
    root = Path(directory)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1',0)); port = sock.getsockname()[1]
    options['file_path'] = str(root/'audit.json')
    config = root/'config.json'
    config.write_text(json.dumps({'audit':audit,'unsafe_allow_api_audit_creation':False}))
    def call(path, body=None):
        data = None if body is None else json.dumps(body).encode()
        request=urllib.request.Request(f'http://127.0.0.1:{port}/v1/{path}',data=data,
            headers={'X-Vault-Token':'local-audit-test','Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=2) as response:
            return response.read()
    with (root/'server.log').open('w') as log:
        process=subprocess.Popen([sys.argv[2],'server','-dev','-dev-root-token-id=local-audit-test',
            f'-dev-listen-address=127.0.0.1:{port}',f'-config={config}'],stdout=log,stderr=log)
        try:
            for attempt in range(100):
                try:
                    call('sys/health'); break
                except OSError:
                    assert process.poll() is None, 'OpenBao exited during audit setup'
                    time.sleep(0.1)
            else: raise AssertionError('OpenBao not ready')
            try:
                call('sys/audit/api-test', {'type':'file','options':{'file_path':'discard'}})
            except urllib.error.HTTPError as error:
                assert error.code in (400,403)
                error.close()
            else:
                raise AssertionError('API-created file audit unexpectedly allowed')
            secret='synthetic-secret-must-be-hmac-protected'
            call('secret/data/smoke',{'data':{'value':secret}})
            call('secret/data/smoke')
            text=(root/'audit.json').read_text()
            assert secret not in text and 'hmac-sha256:' in text, 'audit values not protected'
            assert (root/'audit.json').stat().st_mode & 0o777 == 0o600
            (root/'audit.json').rename(root/'audit.json.1')
            process.send_signal(signal.SIGHUP)
            for attempt in range(100):
                if (root/'audit.json').exists(): break
                time.sleep(0.1)
            call('secret/data/smoke')
            assert (root/'audit.json').stat().st_size > 0, 'audit did not reopen after rotation'
            print('PASS: declarative audit, protected values, private mode, SIGHUP rotation')
        finally:
            process.terminate(); process.wait(timeout=10)
