"""Discovery's wiki-cron seed must stay out of the activation transaction.

Observed 2026-10-19: activation restarted docker-hermes-agent, the container
needed ~3 min to become ready, the seed's fixed 120 s readiness gate expired and
the unit exited 1. `switch-to-configuration` treats that as a failed activation,
so deploy-rs magic rollback discarded an otherwise good generation. The seed is
driven by a timer instead: activation cannot depend on container readiness, and
the timer retries a failed seed.
"""

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).parents[2]

SERVICE = "nixosConfigurations.discovery.config.systemd.services.hermes-wiki-cron-seed"
TIMER = "nixosConfigurations.discovery.config.systemd.timers.hermes-wiki-cron-seed"


def nix_eval(attribute: str):
    result = subprocess.run(
        ["nix", "eval", "--json", f".#{attribute}"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def test_wiki_seed_is_not_started_by_activation():
    wanted_by = nix_eval(f"{SERVICE}.wantedBy") or []
    assert "multi-user.target" not in wanted_by
    assert "timers.target" not in wanted_by


def test_wiki_seed_is_driven_by_a_timer():
    assert nix_eval(f"{TIMER}.wantedBy") == ["timers.target"]
    assert nix_eval(f"{TIMER}.timerConfig.Unit") == "hermes-wiki-cron-seed.service"


def test_timer_covers_boot_and_failed_runs():
    assert nix_eval(f"{TIMER}.timerConfig.OnBootSec") not in (None, "")
    assert nix_eval(f"{TIMER}.timerConfig.OnUnitActiveSec") not in (None, "")
