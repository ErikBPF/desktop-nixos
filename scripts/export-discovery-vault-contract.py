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


def export(source: pathlib.Path) -> dict[str, object]:
    text = source.read_text()
    pending: list[str] = []
    renders: list[dict[str, object]] = []
    for line in text.splitlines():
        if "contents = " in line:
            pending = NAME.findall(line)
            continue
        match = DESTINATION.match(line)
        if match and pending:
            renders.append({"destination": match.group(1), "names": sorted(pending)})
            pending = []
    names = sorted({name for render in renders for name in render["names"]})
    return {
        "schema_version": 1,
        "owner": "desktop-nixos",
        "source": "modules/hosts/discovery/vault.nix",
        "source_sha256": hashlib.sha256(text.encode()).hexdigest(),
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
