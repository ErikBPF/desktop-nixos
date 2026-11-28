"""The nightly closure warm must finish inside the unit's start timeout.

The warm builds one host at a time with a per-host `timeout`, so the worst case
is the host count times that timeout plus the git sync and evaluation before
the first build. That total has to fit inside `TimeoutStartSec` in the Orion
unit, otherwise the last host is killed by the unit rather than by its own
budget and the failure summary never prints.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "modules" / "services" / "nix-cache.nix"
ORION = ROOT / "modules" / "hosts" / "orion" / "default.nix"
OVERHEAD_MINUTES = 20  # git clone/fetch/reset, flake evaluation, unit start


def test_warm_attempt_budget_fits_unit_timeout():
    cache = CACHE.read_text()
    hosts = re.search(r"for host in ([a-z ]+); do", cache).group(1).split()
    per_host_seconds = int(re.search(r"timeout (\d+) nix build", cache).group(1))
    ceiling_minutes = int(re.search(r'TimeoutStartSec = "(\d+)min";', ORION.read_text()).group(1))

    assert hosts, "warm host list is empty"
    attempts_minutes = len(hosts) * per_host_seconds // 60
    total_minutes = attempts_minutes + OVERHEAD_MINUTES
    assert total_minutes <= ceiling_minutes, (
        f"{len(hosts)} hosts x {per_host_seconds}s = {attempts_minutes}min "
        f"+ {OVERHEAD_MINUTES}min overhead exceeds the {ceiling_minutes}min ceiling"
    )
