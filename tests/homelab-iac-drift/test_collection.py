"""Exercise the rendered drift collector with harmless local textfiles."""
import os
from pathlib import Path
import shutil
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def block(text, name):
    start = text.index(name)
    end = text.index('{', start)+1
    depth = 1
    while depth:
        depth += (text[end]=='{')-(text[end]=='}')
        end += 1
    return text[start:end]


def test_protected_drift_collector_rejects_spoof_and_keeps_backup(tmp_path):
    alloy = os.environ.get('ALLOY_BIN') or shutil.which('alloy')
    assert alloy, 'provide pinned Alloy in ALLOY_BIN'
    evaluated = subprocess.run(['nix','eval','--offline','--impure','--raw','--expr',
        '(import ./tests/homelab-iac-drift/evaluate.nix).alloy'],cwd=ROOT,text=True,capture_output=True,check=True).stdout
    full=tmp_path/'full.alloy';full.write_text(evaluated)
    subprocess.run([alloy,'validate',str(full)],check=True,capture_output=True)
    trusted=tmp_path/'trusted';trusted.mkdir()
    legacy=tmp_path/'legacy';legacy.mkdir()
    (trusted/'drift.prom').write_text('homelab_iac_drift_outcome{instance="forged",path="private"} 3\n')
    (legacy/'backup.prom').write_text('backup_last_success_seconds 123\nhomelab_iac_drift_outcome{instance="forged"} 999\n')
    text='\n'.join(block(evaluated,n) for n in ('prometheus.exporter.unix "iac_drift"',
        'prometheus.scrape "iac_drift"','prometheus.relabel "iac_drift"','prometheus.relabel "host_legacy"'))
    text=text.replace('/var/lib/homelab-iac-drift-metrics',str(trusted)).replace(
        'prometheus.remote_write.prometheus.receiver','prometheus.echo.fixture.receiver').replace(
        'scrape_interval = "30s"','scrape_interval = "1s"\n scrape_timeout = "1s"')
    text+=f'''
    prometheus.exporter.unix "legacy" {{
      set_collectors = ["textfile"]
      textfile {{ directory = "{legacy}" }}
    }}
    prometheus.scrape "legacy" {{
      targets = prometheus.exporter.unix.legacy.targets
      forward_to = [prometheus.relabel.host_legacy.receiver]
      scrape_interval = "1s"
      scrape_timeout = "1s"
    }}
    prometheus.echo "fixture" {{}}
    '''
    config=tmp_path/'fixture.alloy';config.write_text(text)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
    log=tmp_path/'alloy.log'
    with log.open('w') as stream:
        process=subprocess.Popen([alloy,'run','--disable-reporting',f'--server.http.listen-addr=127.0.0.1:{port}',
            f'--storage.path={tmp_path / "data"}',str(config)],stdout=stream,stderr=stream)
        try:
            deadline=time.monotonic()+15
            while time.monotonic()<deadline:
                text=log.read_text()
                if 'backup_last_success_seconds' in text and 'homelab_iac_drift_outcome' in text:break
                assert process.poll() is None,text
                time.sleep(.2)
            samples='\n'.join(line for line in text.splitlines() if 'homelab_iac_drift_outcome' in line)
            assert 'backup_last_success_seconds' in text
            assert 'discovery' in samples
            assert '999' not in samples and 'forged' not in samples and 'private' not in samples
        finally:
            process.terminate();process.wait(timeout=10)
