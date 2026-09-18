"""Compare evaluated managed-host derivations without building or activating."""

import json
from pathlib import Path
import re
import subprocess
import sys


def evaluate(reference, attribute, expression, phase):
    try:
        result = subprocess.run(
            ["nix", "eval", "--json", "--offline", "--no-write-lock-file",
             "--option", "allow-import-from-derivation", "false",
             "--apply", expression, reference + "#" + attribute],
            capture_output=True, text=True, check=True,
        )
        return json.loads(result.stdout)
    except (OSError, subprocess.CalledProcessError, ValueError):
        sys.exit(f"upgrade-impact: {phase} evaluation failed")


def snapshot(reference, phase, selector):
    if not reference or reference.startswith("-") or "#" in reference:
        sys.exit(f"upgrade-impact: invalid {phase} snapshot")
    names = evaluate(reference, "fleet.hosts", selector, phase)
    if (not isinstance(names, list) or not names
            or any(not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", name)
                   for name in names)):
        sys.exit(f"upgrade-impact: invalid {phase} host set")
    identities = {}
    # ponytail: sequential processes bound memory to one host; parallelize only with measured headroom.
    for name in names:
        value = evaluate(reference, "nixosConfigurations",
                         f'configs: configs."{name}".config.system.build.toplevel.drvPath', phase)
        if not isinstance(value, str) or not re.fullmatch(
            r"/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[A-Za-z0-9+._?=-]+\.drv", value
        ):
            sys.exit(f"upgrade-impact: invalid {phase} derivation identity")
        identities[name] = value
    return identities


if len(sys.argv) != 3:
    sys.exit("usage: upgrade-impact.py before after")
try:
    selector = Path(__file__).with_name("upgrade-hosts.nix").read_text()
except OSError:
    sys.exit("upgrade-impact: host selector unavailable")
before = snapshot(sys.argv[1], "before", selector)
after = snapshot(sys.argv[2], "after", selector)
if before.keys() != after.keys():
    sys.exit("upgrade-impact: managed host topology changed")
print(json.dumps({
    "affected": {name: {"before": before[name], "after": after[name]}
                 for name in sorted(before) if before[name] != after[name]},
    "unchanged": {name: before[name] for name in sorted(before) if before[name] == after[name]},
}, sort_keys=True))
