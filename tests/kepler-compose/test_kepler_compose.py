import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/hosts/kepler/compose.nix"
JUSTFILE = ROOT / "justfile"


def test_enabled_stacks_include_backup_and_exclude_empty_profile():
    text = MODULE.read_text()
    assert '"sync"' in text
    assert '"security"' in text
    assert '"docs-search"' not in text


def test_esp_verifier_checks_exact_declared_units_individually():
    module = MODULE.read_text()
    stacks = module.split("stacks = [", 1)[1].split("];", 1)[0]
    declared = re.findall(r'"([^"]+)"', stacks)
    recipe = JUSTFILE.read_text().split(
        "verify-kepler-after-esp-migration:", 1
    )[1].split("\n\n", 1)[0]

    compose_units = set(re.findall(r"podman-compose-[a-z0-9-]+\.service", recipe))
    assert compose_units == {f"podman-compose-{stack}.service" for stack in declared}
    assert "for unit in sshd tailscaled syncthing nfs-server; do" in recipe
    assert 'sudo systemctl is-active --quiet "$unit" || exit 1' in recipe
    assert 'systemctl --user is-active --quiet "$unit" || exit 1' in recipe
