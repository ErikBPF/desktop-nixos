#!/usr/bin/env python3
"""Export the value-free Discovery Vault Agent dotenv surface."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re


NAME = re.compile(r"([A-Z][A-Z0-9_]*)=\{\{")
DESTINATION = re.compile(r'^\s*destination = "([^"]+)"')
PERMS = re.compile(r'^\s*perms = "([0-7]{4})"')
CHGRP = re.compile(r'^\s*command = \["[^"]*/chgrp", "([^"]+)", "([^"]+)"\]')


def export(source: pathlib.Path) -> dict[str, object]:
    text = source.read_text()
    pending: list[str] = []
    current: dict[str, object] | None = None
    renders: list[dict[str, object]] = []
    for line in text.splitlines():
        if "contents = " in line:
            pending = NAME.findall(line)
            continue
        match = DESTINATION.match(line)
        if match and pending:
            current = {"destination": match.group(1), "names": sorted(pending)}
            pending = []
            continue
        match = PERMS.match(line)
        if match and current:
            current["perms"] = match.group(1)
            renders.append(current)
            current = None
            continue
        match = CHGRP.match(line)
        if match:
            group, destination = match.groups()
            render = next(
                (row for row in renders if row["destination"] == destination), None
            )
            if render is not None:
                render["group"] = group
    names = sorted({name for render in renders for name in render["names"]})
    return {
        "schema_version": 1,
        "owner": "desktop-nixos",
        "source": "modules/hosts/discovery/vault.nix",
        "source_sha256": hashlib.sha256(text.encode()).hexdigest(),
        "service_identity": {
            "unit": "vault-agent.service",
            "user": "root",
            "group": "root",
            "runtime_directory": "/run/vault-agent",
        },
        "names": names,
        "renders": renders,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(export(args.source), indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
