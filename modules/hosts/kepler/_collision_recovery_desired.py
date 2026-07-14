#!/usr/bin/env python3
"""Render deterministic, value-free desired Kepler Compose metadata locally."""

import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tomllib


SERVARR_COMMIT = "1805e1d5c40e0281660088732823dad9a138bd64"
STACKS = ("infra", "ai-serving", "docs-search", "orchestration")
VARIABLE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?:(?::-|:\?)[^}]*)?\}")
DUMMY_PREFIX = "__K1_DUMMY_"
REQUIRED_LABELS = (
    "com.docker.compose.project",
    "com.docker.compose.service",
)


class DesiredHalt(Exception):
    pass


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def _commit(root):
    result = subprocess.run(
        ("git", "rev-parse", "HEAD"), cwd=root, check=True,
        capture_output=True, text=True,
    )
    return result.stdout.strip()


def _variables(files):
    names = set()
    for path in files:
        names.update(VARIABLE.findall(path.read_text(encoding="utf-8")))
    return sorted(names)


def _dummy_environment(names):
    environment = {"PATH": os.environ.get("PATH", "")}
    for name in names:
        value = f"{DUMMY_PREFIX}{name}__"
        if name.endswith(("_POOL", "_PATH", "_DIR")):
            value = "/" + value
        environment[name] = value
    return environment


def _restore_templates(value):
    if not isinstance(value, str):
        return value
    for name in VARIABLE_NAMES:
        value = value.replace(f"/{DUMMY_PREFIX}{name}__", f"${{{name}}}")
        value = value.replace(f"{DUMMY_PREFIX}{name}__", f"${{{name}}}")
    return value


def _source(source, root):
    source = _restore_templates(source)
    try:
        relative = pathlib.Path(source).relative_to(root)
    except (ValueError, TypeError):
        return source
    return f"./{relative.as_posix()}"


def _mount(mount, root):
    item = {
        "source": _source(mount.get("source", ""), root),
        "target": mount.get("target", ""),
        "type": mount.get("type", ""),
    }
    if mount.get("read_only"):
        item["read_only"] = True
    return item


def _digest_status(image):
    if re.search(r"@sha256:[0-9a-f]{64}$", image):
        return "immutable-registry-digest"
    repository = image.split(":", 1)[0]
    if repository.startswith("kepler/"):
        return "local-provenance-required"
    return "registry-digest-required"


def _compose_config(root, stack, environment):
    path = root / f"{stack}.compose.yml"
    command = (
        "docker", "compose", "--env-file", "/dev/null", "-p", stack,
        "-f", str(path), "--profile", "*", "config", "--format", "json",
        "--no-env-resolution", "--no-path-resolution",
    )
    result = subprocess.run(
        command, cwd=root, env=environment, check=True,
        capture_output=True, text=True,
    )
    return json.loads(result.stdout)


def generate(root, expected_commit=SERVARR_COMMIT):
    root = pathlib.Path(root).resolve()
    files = [root / f"{stack}.compose.yml" for stack in STACKS]
    files.append(root / "secretspec.toml")
    if any(not path.is_file() for path in files):
        raise DesiredHalt("required Kepler Compose or SecretSpec file missing")
    commit = _commit(root)
    if commit != expected_commit:
        raise DesiredHalt(f"Servarr revision drift: expected {expected_commit}, got {commit}")
    with (root / "secretspec.toml").open("rb") as handle:
        secretspec = tomllib.load(handle)
    if secretspec.get("project", {}).get("name") != "kepler":
        raise DesiredHalt("SecretSpec project must be kepler")
    expected_profiles = {"default", *STACKS}
    if set(secretspec.get("profiles", {})) != expected_profiles:
        raise DesiredHalt("SecretSpec profiles drifted from Kepler stack contract")

    global VARIABLE_NAMES
    VARIABLE_NAMES = _variables(files)
    environment = _dummy_environment(VARIABLE_NAMES)
    services = []
    for stack in STACKS:
        config = _compose_config(root, stack, environment)
        for service_name, service in sorted(config.get("services", {}).items()):
            image = service.get("image", "")
            services.append({
                "container_name": service.get("container_name", f"{stack}-{service_name}-1"),
                "digest_status": _digest_status(image),
                "image": image,
                "mounts": sorted(
                    (_mount(mount, root) for mount in service.get("volumes", [])),
                    key=lambda item: (item["source"], item["target"], item["type"]),
                ),
                "networks": sorted(service.get("networks", {})),
                "project": stack,
                "required_labels": {
                    REQUIRED_LABELS[0]: stack,
                    REQUIRED_LABELS[1]: service_name,
                },
                "service": service_name,
            })
    desired = {
        "schema": "kepler-collision-desired-v1",
        "servarr_commit": commit,
        "secretspec_project": "kepler",
        "source_sha256": {
            path.name: hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(files)
        },
        "stacks": list(STACKS),
        "services": sorted(services, key=lambda item: (item["project"], item["service"])),
    }
    rendered = canonical(desired)
    if DUMMY_PREFIX.encode() in rendered:
        raise DesiredHalt("synthetic environment marker escaped into desired state")
    return {
        "desired": desired,
        "desired_sha256": hashlib.sha256(rendered).hexdigest(),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--servarr-root", required=True)
    parser.add_argument("--expected-commit", default=SERVARR_COMMIT)
    args = parser.parse_args(argv)
    try:
        print(json.dumps(generate(args.servarr_root, args.expected_commit), sort_keys=True))
    except (DesiredHalt, OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"desired-state halted: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
