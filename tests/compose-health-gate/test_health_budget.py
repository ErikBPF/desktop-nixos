"""Compose stack units carry a configurable, bounded health gate.

These are home-manager USER units (`systemd.user.startServices = false`), so they
run on boot linger and from `just kick-stack`, not inside `nixos-rebuild switch`.
Observed 2026-10-19: the hard-coded 60x2 s budget was shorter than the service's
real start, so a slow container failed the stack unit. The budget is now a
declared option, sized from the service's own start period.
"""

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).parents[2]
COMPOSE = "nixosConfigurations.discovery.config.home-manager.users.erik.systemd.user.services"
CONFIG = "nixosConfigurations.discovery.config.homelab.compose"


def nix_eval(attribute: str):
    result = subprocess.run(
        ["nix", "eval", "--json", f".#{attribute}"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def test_gated_stack_carries_a_health_gate():
    gate = nix_eval(f'{COMPOSE}."podman-compose-plex".Service.ExecStartPost')
    assert len(gate) == 1


def test_ungated_stack_has_no_health_gate():
    # Negative control: firmware declares no health containers, so the gate must
    # stay absent rather than silently waiting on nothing.
    assert nix_eval(f'{COMPOSE}."podman-compose-firmware".Service.ExecStartPost') in (None, [], "")


def test_gate_budget_is_a_declared_option():
    assert nix_eval(f"{CONFIG}.healthGateTimeoutSeconds") == 180
    assert nix_eval(f"{CONFIG}.healthGateTimeoutOverrides") == {}


def test_gate_script_uses_the_declared_budget():
    unit = (ROOT / "modules/server/orchestration.nix").read_text()
    gate = unit.split('pkgs.writeShellScript "secretspec-${name}-health"', 1)[1]
    gate = gate.split("ExecStartPost", 1)[0]
    assert "healthGateTimeout" in gate
    assert "$SECONDS" in gate
