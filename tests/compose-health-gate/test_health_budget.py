"""Compose stack units carry a configurable, bounded health gate.

These are home-manager USER units (`systemd.user.startServices = false`), so they
run on boot linger and from `just kick-stack`, not inside `nixos-rebuild switch`.
Observed 2026-10-19: the hard-coded 60x2 s budget was shorter than the service's
real start, so a slow container failed the stack unit. The budget is now a
declared option, sized from the service's own start period.
"""

import json
import os
import re
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).parents[2]
COMPOSE = "nixosConfigurations.discovery.config.home-manager.users.erik.systemd.user.services"
CONFIG = "nixosConfigurations.discovery.config.homelab.compose"


def nix_eval(attribute: str, apply: str | None = None):
    command = ["nix", "eval", "--json", "--no-write-lock-file", f".#{attribute}"]
    if apply is not None:
        command.extend(["--apply", apply])
    result = subprocess.run(
        command,
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


def test_cutover_profiles_keep_every_declared_health_container():
    health = nix_eval(f"{CONFIG}.secretSpecRuntimeHealthContainers")
    assert health["ha-harness"] == ["ha-harness"]
    assert health["homepage"] == ["homepage"]
    assert health["tools"] == ["searxng", "cyberchef"]


@pytest.fixture(scope="module")
def tools_health_script():
    # Evaluate the real service with a short test budget; never start the unit.
    context = nix_eval("nixosConfigurations.discovery", '''system: let
      config = (system.extendModules {
        modules = [{ homelab.compose.healthGateTimeoutSeconds = 1; }];
      }).config;
    in builtins.getContext (toString (builtins.head
      config.home-manager.users.erik.systemd.user.services.podman-compose-tools.Service.ExecStartPost))''')
    assert len(context) == 1
    derivation = next(iter(context))
    description = json.loads(subprocess.check_output(
        ["nix", "derivation", "show", derivation], cwd=ROOT, text=True,
    ))
    value = next(iter(description.get("derivations", description).values()))
    attributes = value.get("structuredAttrs", value.get("env"))
    if "__json" in attributes:
        attributes = json.loads(attributes["__json"])
    return attributes["text"]


@pytest.mark.parametrize("second_status, expected", [
    ("healthy", 0),
    ("unhealthy", 1),
    ("starting", 1),
    ("inspect-error", 1),
])
def test_every_container_must_be_healthy(tools_health_script, tmp_path, second_status, expected):
    docker = tmp_path / "docker"
    calls = tmp_path / "calls"
    docker.write_text('''#!/bin/sh
set -eu
[ "$#" -eq 4 ] && [ "$1" = inspect ] && [ "$2" = --format ]
printf '%s\\n' "$4" >> "$HEALTH_CALLS"
case "$4" in
  searxng) printf 'healthy\\n' ;;
  cyberchef)
    [ "$SECOND_STATUS" != inspect-error ] || exit 1
    printf '%s\\n' "$SECOND_STATUS" ;;
  *) exit 99 ;;
esac
''')
    docker.chmod(0o700)
    script, replacements = re.subn(
        r"/nix/store/[^\s\"']+/bin/docker", shlex.quote(str(docker)), tools_health_script,
    )
    assert replacements == 1
    # Derivation metadata does not realize coreutils; keep the real delay using
    # the test environment's sleep executable.
    sleep = shutil.which("sleep")
    assert sleep is not None, "sleep must be available for the bounded health probe"
    script, replacements = re.subn(
        r"/nix/store/[^\s\"']+/bin/sleep", shlex.quote(sleep), script,
    )
    assert replacements == 1
    result = subprocess.run(
        ["bash", "-c", script], capture_output=True, text=True, timeout=5,
        env={"PATH": os.environ["PATH"], "HEALTH_CALLS": str(calls), "SECOND_STATUS": second_status},
    )
    assert result.returncode == expected, result.stderr
    assert calls.read_text().splitlines() == ["searxng", "cyberchef"]
