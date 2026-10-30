#!/usr/bin/env python3
"""Export the value-free Discovery Vault Agent dotenv surface."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import subprocess


NAME = re.compile(r"([A-Z][A-Z0-9_]*)=\{\{")
DESTINATION = re.compile(r'^\s*destination = "([^"]+)"')
PERMS = re.compile(r'^\s*perms = "([0-7]{4})"')
CHGRP = re.compile(r'^\s*command = \["[^"]*/chgrp", "([^"]+)", "([^"]+)"\]')


def export(source: pathlib.Path) -> dict[str, object]:
    source = source.resolve()
    root = source.parents[3]
    relative = source.relative_to(root).as_posix()
    if relative != "modules/hosts/discovery/_vault-agent.nix":
        raise ValueError("source must be Discovery's active _vault-agent.nix")
    service = json.loads(subprocess.check_output([
        "nix", "eval", "--json", "--no-write-lock-file",
        f"{root}#nixosConfigurations.discovery.config.systemd.services.vault-agent.serviceConfig",
        "--apply", '''s: {
          user = s.User or "root";
          group = s.Group or null;
          runtime_directory = s.RuntimeDirectory;
          context = builtins.getContext s.ExecStart;
        }''',
    ], text=True))
    if service["group"] is None:
        if service["user"] != "root":
            raise ValueError("non-root service requires an explicit group")
        service["group"] = "root"
    derivations = [path for path in service["context"] if path.endswith("-vault-agent.hcl.drv")]
    if len(derivations) != 1:
        raise ValueError("expected exactly one evaluated vault-agent.hcl derivation")
    description = json.loads(subprocess.check_output(
        ["nix", "derivation", "show", derivations[0]], text=True,
    ))
    derivation = next(iter(description.get("derivations", description).values()))
    attributes = derivation.get("structuredAttrs", derivation["env"])
    if "__json" in attributes:
        attributes = json.loads(attributes["__json"])
    text = attributes["text"]
    pending: list[str] = []
    current: dict[str, object] | None = None
    renders: list[dict[str, object]] = []
    for line in text.splitlines():
        if "contents = " in line:
            pending = NAME.findall(line)
            continue
        match = DESTINATION.match(line)
        if match and pending:
            current = {"destination": match.group(1), "names": sorted(pending), "group": service["group"]}
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
        "source": relative,
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "service_identity": {
            "unit": "vault-agent.service",
            "user": service["user"],
            "group": service["group"],
            "runtime_directory": f"/run/{service['runtime_directory']}",
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
