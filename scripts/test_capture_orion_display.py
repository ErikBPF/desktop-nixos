"""Run with python scripts/test_capture_orion_display.py; no host access."""

import os
from pathlib import Path
import subprocess
import tempfile


with tempfile.TemporaryDirectory() as directory:
    timeout = Path(directory) / "timeout"
    timeout.write_text(
        '#!/bin/sh\nshift 3\nprintf "PROBE %s\\n" "$*"\n'
        '[ "$1" != uname ] || exit 124\n'
    )
    timeout.chmod(0o700)
    result = subprocess.run(
        ["bash", str(Path(__file__).with_name("capture-orion-display.sh"))],
        env={**os.environ, "PATH": directory + os.pathsep + os.environ["PATH"]},
        capture_output=True,
        text=True,
        check=True,
    )
    assert "CAPTURE_FAILED status=124" in result.stdout
    assert "PROBE sudo -n journalctl -k -b" in result.stdout
    assert "Snapshot finished" in result.stdout
    assert result.stdout.index("CAPTURE_FAILED") < result.stdout.index("PROBE sudo")
print("PASS: timed-out probe preserves later journal capture")
