"""Run the evaluated production relabel stages against local fixture metrics."""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def block(config, name):
    start = config.index(name)
    opening = config.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (config[end] == "{") - (config[end] == "}")
        end += 1
    return config[start:end]


def test_local_collector_rejects_legacy_collision_and_overwrites_identity(tmp_path):
    alloy = os.environ.get("ALLOY_BIN") or shutil.which("alloy")
    assert alloy, "run with the pinned Alloy package in ALLOY_BIN"
    evaluated = subprocess.run([
        "nix", "eval", "--offline", "--impure", "--raw", "--expr",
        '(import ./tests/host-integrity/_fixture.nix {output = "alloy";})',
    ], cwd=ROOT, text=True, capture_output=True, check=True).stdout
    full = tmp_path / "full.alloy"
    full.write_text(evaluated)
    subprocess.run([alloy, "validate", str(full)], check=True, capture_output=True, text=True)
    legacy = tmp_path / "legacy"
    trusted = tmp_path / "trusted"
    legacy.mkdir()
    trusted.mkdir()
    (legacy / "backup.prom").write_text('backup_last_success_seconds 123\nhost_integrity_findings{instance="forged",check="store"} 999\n')
    (trusted / "store.prom").write_text('host_integrity_findings{instance="forged",check="store",path="private"} 3\nhost_integrity_findings{instance="forged",check="unknown"} 8\n')
    selected = [block(evaluated, name) for name in (
        'prometheus.exporter.unix "host_integrity"',
        'prometheus.scrape "host_integrity"',
        'prometheus.relabel "host_integrity"',
        'prometheus.relabel "host_legacy"',
    )]
    config = '\n'.join(selected).replace('/var/lib/host-integrity-metrics', str(trusted)).replace(
        'prometheus.remote_write.prometheus.receiver', 'prometheus.echo.fixture.receiver'
    ).replace('scrape_interval = "30s"', 'scrape_interval = "1s"\n scrape_timeout = "1s"')
    config += f'''
    prometheus.exporter.unix "fixture_legacy" {{
      set_collectors = ["textfile"]
      textfile {{ directory = "{legacy}" }}
    }}
    prometheus.scrape "fixture_legacy" {{
      targets = prometheus.exporter.unix.fixture_legacy.targets
      forward_to = [prometheus.relabel.host_legacy.receiver]
      scrape_interval = "1s"
      scrape_timeout = "1s"
    }}
    prometheus.echo "fixture" {{}}
    '''
    fixture = tmp_path / "fixture.alloy"
    fixture.write_text(config)
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    log = tmp_path / "alloy.log"
    with log.open("w") as stream:
        proc = subprocess.Popen([alloy, "run", "--disable-reporting",
            f"--server.http.listen-addr=127.0.0.1:{port}",
            f"--storage.path={tmp_path / 'data'}", str(fixture)], stdout=stream, stderr=stream)
        try:
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                text = log.read_text()
                if 'backup_last_success_seconds' in text and 'host_integrity_findings' in text:
                    break
                assert proc.poll() is None, text
                time.sleep(0.2)
            assert 'backup_last_success_seconds' in text, text
            assert 'host_integrity_findings' in text, text
            samples = "".join(json.loads(line.split(" metrics=", 1)[1])
                              for line in text.splitlines()
                              if ' metrics=' in line and 'host_integrity_findings' in line)
            assert '} 999 ' not in samples, samples
            assert '} 3 ' in samples, samples
            assert 'integrity-fixture' in samples, samples
            assert 'forged' not in samples and 'private' not in samples and 'unknown' not in samples, samples
        finally:
            proc.terminate()
            proc.wait(timeout=10)
