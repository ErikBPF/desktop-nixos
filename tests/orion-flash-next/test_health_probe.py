"""Execute the shipped readiness check without contacting Orion."""
import os
from pathlib import Path
import shutil
import subprocess
import textwrap

import pytest


ROOT = Path(__file__).parents[2]


@pytest.mark.parametrize(
    ("body", "curl_exit", "expected"),
    [
        ('{"status":"ok","service":"strata","loaded":true}', 0, "1"),
        ('{"status":"ok","service":"strata","loaded":false}', 0, "0"),
        ('{"status":"ok","service":"other","loaded":true}', 0, "0"),
        ('{"status":"ok","service":"strata"}', 0, "0"),
        ('{"status":"starting","service":"strata","loaded":true}', 0, "0"),
        ('{"status":"ok","service":"strata","loaded":1}', 0, "0"),
        ('[{"status":"ok","service":"strata","loaded":true}]', 0, "0"),
        ('not JSON: "status":"ok"', 0, "0"),
        ('{"status":"ok","service":"strata","loaded":true}', 22, "0"),
        ("", 7, "0"),
    ],
)
def test_probe_requires_ready_official_runtime(tmp_path, body, curl_exit, expected):
    module = (ROOT / "modules/hosts/discovery/monitoring.nix").read_text()
    probe = textwrap.dedent(module.split("          healthy=0\n", 1)[1].split("          probed_at=", 1)[0])
    curl = tmp_path / "curl"
    curl.write_text('#!/bin/sh\nprintf "%s" "$PROBE_BODY"\nexit "$PROBE_CURL_EXIT"\n')
    curl.chmod(0o755)
    probe = probe.replace("${pkgs.curl}/bin/curl", str(curl))
    probe = probe.replace("${pkgs.jq}/bin/jq", shutil.which("jq"))
    result = subprocess.run(
        ["bash", "-eu", "-c", 'healthy=0\n' + probe + '\nprintf "%s" "$healthy"'],
        env={**os.environ, "PROBE_BODY": body, "PROBE_CURL_EXIT": str(curl_exit)},
        capture_output=True,
        text=True,
        check=True,
    )
    assert result.stdout == expected
