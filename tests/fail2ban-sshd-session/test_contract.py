import json
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).parents[2]


@pytest.mark.parametrize("host", ["vanguard", "voyager"])
def test_sshd_jail_matches_session_process(host):
    result = subprocess.run(
        [
            "nix",
            "eval",
            "--json",
            f".#nixosConfigurations.{host}.config.services.fail2ban.jails.sshd.settings.journalmatch",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )

    assert "_COMM=sshd-session" in json.loads(result.stdout)
