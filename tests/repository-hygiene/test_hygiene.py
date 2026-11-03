"""Repository hygiene invariants for the simplification change.

One runnable check for the properties the simplification claims. Each assertion
maps to a rule in docs/proposals/2026-10-31-repository-simplification.md.
"""

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
JUSTFILES = [ROOT / "justfile", *sorted((ROOT / "just").glob("*.just"))]

RETAINED_DISCOVERY = {
    "discovery-swag-restore-drill",
    "discovery-adguard-restore-preflight",
    "discovery-adguard-restore-seed",
    "discovery-adguard-restore-finalize",
    "discovery-adguard-restore-drill",
    "discovery-adguard-exporter-diagnostic",
}

REMOVED_EXACT = {
    "discovery-migration-inventory",
    "discovery-telstar-state-inventory",
    "p3-generic-dhcp-client",
    "p3-adguard-outage-prepare",
    "p3-adguard-outage-plan",
    "p3-adguard-outage-observe",
    "p3-adguard-outage-execute",
    "p3-adguard-observation-recover",
    "p3-adguard-outage-cleanup",
    "drtest-vm-build",
    "drtest-vm-start",
    "drtest-vm-stop",
    "drtest-vm-wait",
    "drtest-vm-ssh",
    "voyager-vm-build",
    "voyager-vm-test",
    "voyager-vm-start",
    "voyager-vm-stop",
    "voyager-vm-smoke",
    "prepare-kepler-fast-state",
    "finalize-kepler-fast-state",
    "kepler-retire-legacy-retrieval",
    "orion-retire-legacy-llama",
    "kepler-retire-ai-serving-user-approved",
    "p2-iac-plan-equivalence",
    "index-spark-docs",
    "rebuild-docs-search",
    "send-discord-samples",
    "grafana-alert-status",
}

REQUIRED_CAPABILITIES = {
    "discovery-swag-restore-drill",
    "discovery-adguard-restore-drill",
    "discovery-harbor-restore-drill",
    "discovery-haos-boot-drill",
    "kepler-recovery-inventory",
    "deploy-rs",
    "update-safe",
    "p3-dns-preflight",
    "p3-dns-verify",
}

REMOVED_PREFIX = re.compile(r"^discovery-(swag|adguard|docker|esp)-")
GATE_FILES = [ROOT / ".github" / "workflows", *JUSTFILES]


def _recipe_names():
    out = subprocess.run(
        ["just", "--summary"], cwd=ROOT, capture_output=True, text=True, check=True
    )
    return set(out.stdout.split())


def _gate_text():
    parts = []
    for path in GATE_FILES:
        if path.is_dir():
            parts.extend(p.read_text() for p in path.glob("*.yml"))
        elif path.exists():
            parts.append(path.read_text())
    return "\n".join(parts)


def test_finished_migration_recipes_are_gone():
    names = _recipe_names()
    leftovers = sorted(
        name
        for name in names
        if REMOVED_PREFIX.match(name) and name not in RETAINED_DISCOVERY
    )
    assert leftovers == []
    assert sorted(REMOVED_EXACT & names) == []
    missing = sorted(REQUIRED_CAPABILITIES - names)
    assert missing == []


def test_no_moved_pointer_stubs():
    offenders = []
    for path in (ROOT / "docs").rglob("*.md"):
        if "# Moved" in path.read_text().splitlines():
            offenders.append(str(path.relative_to(ROOT)))
    assert offenders == []


def test_every_test_directory_is_gated_or_manual():
    manual = ROOT / "tests" / "MANUAL.md"
    gated = _gate_text()
    if manual.exists():
        gated += manual.read_text()
    dirs = sorted(
        p.name
        for p in (ROOT / "tests").iterdir()
        if p.is_dir() and not p.name.startswith("__")
    )
    referenced = set(re.findall(r"tests/([\w.-]+)", gated))
    unlisted = [d for d in dirs if d not in referenced]
    assert unlisted == []


def test_unreferenced_asset_is_removed():
    assert not (ROOT / "config/themes/wallpapers/wallpaper_old.png").exists()


def test_justfile_is_split_by_domain():
    root = (ROOT / "justfile").read_text()
    imports = re.findall(r"^import\s+['\"]just/[^'\"]+\.just['\"]", root, re.M)
    assert imports, "root justfile has no just/*.just imports"
    assert not re.search(r"^mod\s+", root, re.M), "use import, not mod"


if __name__ == "__main__":
    checks = [
        test_finished_migration_recipes_are_gone,
        test_no_moved_pointer_stubs,
        test_every_test_directory_is_gated_or_manual,
        test_unreferenced_asset_is_removed,
        test_justfile_is_split_by_domain,
    ]
    failures = []
    for check in checks:
        try:
            check()
        except AssertionError as exc:
            failures.append(f"{check.__name__}: {exc}")
    if failures:
        print(":: HYGIENE FAILED")
        for failure in failures:
            print(f"  {failure}")
        raise SystemExit(1)
    print(":: HYGIENE OK — every repository invariant holds")
