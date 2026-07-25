import json
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).parents[2]


@pytest.mark.parametrize("host", ["voyager", "vanguard"])
def test_public_host_ships_journal_to_loki(host):
    result = subprocess.run(
        [
            "nix",
            "eval",
            "--json",
            f".#nixosConfigurations.{host}.config.services.vector",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    vector = json.loads(result.stdout)

    assert vector["enable"] is True
    assert vector["settings"]["sinks"]["loki"]["labels"]["host"] == host
    assert vector["settings"]["sinks"]["loki"]["labels"]["source"] == "journal"
