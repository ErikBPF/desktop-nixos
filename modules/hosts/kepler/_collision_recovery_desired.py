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


SERVARR_COMMIT = "8edab1af0252426a55cbf8d15c5dcd06a77a8995"
MIGRATION_STACKS = ("infra", "docs-search")
PROTECTED_STACKS = ()
STACKS = MIGRATION_STACKS + PROTECTED_STACKS
VARIABLE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?:(?::-|:\?)[^}]*)?\}")
DOTENV_NAME = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=", re.MULTILINE)
DUMMY_PREFIX = "__K1_DUMMY_"
REQUIRED_LABELS = (
    "com.docker.compose.project",
    "com.docker.compose.service",
)
REVIEWED_NONSECRET_PATHS = {
    # Kepler's NixOS hardware module owns these mountpoints.  Do not consult
    # the production dotenv while producing a value-free recovery plan.
    "FAST_POOL": "/fast",
    "BULK_POOL": "/bulk",
    "MODELS_PATH": "/fast/models",
}


class DesiredHalt(Exception):
    pass


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def _record_model_identities(provenance, envelope):
    if envelope is None:
        return provenance["model_artifacts"]
    if envelope.get("schema") != "kepler-k1-model-identities-envelope-v1":
        raise DesiredHalt("model identity envelope schema drifted")
    evidence = envelope.get("evidence")
    claimed = envelope.get("evidence_sha256", "")
    if (
        not isinstance(evidence, dict)
        or not re.fullmatch(r"[0-9a-f]{64}", str(claimed))
        or hashlib.sha256(json.dumps(evidence, sort_keys=True, separators=(",", ":")).encode()).hexdigest() != claimed
        or evidence.get("schema") != "kepler-k1-model-identities-v1"
        or evidence.get("algorithm") != "kepler-tree-sha256-v1"
    ):
        raise DesiredHalt("model identity envelope binding invalid")
    records = evidence.get("artifacts")
    if not isinstance(records, list):
        raise DesiredHalt("model identity artifact declarations invalid")
    by_name = {}
    for record in records:
        if not isinstance(record, dict) or set(record) != {
            "algorithm", "artifact", "byte_count", "entry_count", "sha256", "status",
        }:
            raise DesiredHalt("model identity artifact declarations invalid")
        name = record["artifact"]
        if name in by_name or name not in provenance["model_artifacts"]:
            raise DesiredHalt("model identity artifact set drifted")
        if (
            record["algorithm"] != "kepler-tree-sha256-v1"
            or record["status"] != "recorded"
            or not re.fullmatch(r"[0-9a-f]{64}", str(record["sha256"]))
            or isinstance(record["byte_count"], bool)
            or not isinstance(record["byte_count"], int)
            or record["byte_count"] < 0
            or isinstance(record["entry_count"], bool)
            or not isinstance(record["entry_count"], int)
            or record["entry_count"] < 1
        ):
            raise DesiredHalt("model identity artifact declarations invalid")
        by_name[name] = record
    if set(by_name) != set(provenance["model_artifacts"]):
        raise DesiredHalt("model identity artifact set drifted")
    return {
        name: {
            "algorithm": record["algorithm"],
            "byte_count": record["byte_count"],
            "entry_count": record["entry_count"],
            "root": provenance["model_artifacts"][name]["mount"],
            "sha256": record["sha256"],
            "status": "identity-recorded",
        }
        for name, record in sorted(by_name.items())
    }


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
        value = REVIEWED_NONSECRET_PATHS.get(name, f"{DUMMY_PREFIX}{name}__")
        if name.endswith(("_POOL", "_PATH", "_DIR")) and name not in REVIEWED_NONSECRET_PATHS:
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


def _digest_status(image, local_images):
    if re.search(r"@sha256:[0-9a-f]{64}$", image):
        return "immutable-registry-digest"
    repository = image.split(":", 1)[0]
    if repository.startswith("kepler/"):
        if image in local_images:
            return "local-provenance-recorded"
        return "local-provenance-required"
    return "registry-digest-required"


def _model_artifacts(mounts, artifacts):
    sources = {mount["source"] for mount in mounts}
    return sorted(name for name, artifact in artifacts.items() if artifact["mount"] in sources)


def _service_projection(root, stack, project, service_name, service, provenance):
    image = service.get("image", "")
    mounts = sorted(
        (_mount(mount, root) for mount in service.get("volumes", [])),
        key=lambda item: (item["source"], item["target"], item["type"]),
    )
    model_artifacts = _model_artifacts(mounts, provenance["model_artifacts"])
    return {
        "container_name": service.get("container_name", f"{stack}-{service_name}-1"),
        "digest_status": _digest_status(image, provenance["local_images"]),
        "image": image,
        "provenance_status": {
            "local_image": image if image in provenance["local_images"] else None,
            "model_artifacts": model_artifacts,
        },
        "mounts": mounts,
        "networks": sorted(service.get("networks", {})),
        "project": project,
        "required_labels": {
            REQUIRED_LABELS[0]: project,
            REQUIRED_LABELS[1]: service_name,
        },
        "service": service_name,
    }


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


def generate(root, expected_commit=SERVARR_COMMIT, model_identities=None):
    root = pathlib.Path(root).resolve()
    files = [root / f"{stack}.compose.yml" for stack in STACKS]
    files.append(root / "secretspec.toml")
    files.append(root / ".env.example")
    files.append(root / "provenance.json")
    if any(not path.is_file() for path in files):
        raise DesiredHalt("required Kepler Compose or SecretSpec file missing")
    commit = _commit(root)
    if commit != expected_commit:
        raise DesiredHalt(f"Servarr revision drift: expected {expected_commit}, got {commit}")
    with (root / "secretspec.toml").open("rb") as handle:
        secretspec = tomllib.load(handle)
    provenance = json.loads((root / "provenance.json").read_text(encoding="utf-8"))
    if provenance.get("schema") != "kepler-k1-provenance-v1":
        raise DesiredHalt("Kepler provenance schema drifted")
    if set(provenance) != {
        "schema", "legacy_images", "legacy_mounts", "local_images", "model_artifacts",
    }:
        raise DesiredHalt("Kepler provenance declarations drifted")
    if secretspec.get("project", {}).get("name") != "kepler":
        raise DesiredHalt("SecretSpec project must be kepler")
    expected_profiles = {"default", *STACKS}
    if set(secretspec.get("profiles", {})) != expected_profiles:
        raise DesiredHalt("SecretSpec profiles drifted from Kepler stack contract")

    global VARIABLE_NAMES
    VARIABLE_NAMES = _variables(files)
    public_names = set(DOTENV_NAME.findall((root / ".env.example").read_text(encoding="utf-8")))
    missing_paths = set(REVIEWED_NONSECRET_PATHS) - public_names
    if missing_paths:
        raise DesiredHalt(
            "public environment contract omitted reviewed path names: "
            + ", ".join(sorted(missing_paths))
        )
    environment = _dummy_environment(VARIABLE_NAMES)
    services = []
    protected_services = []
    declared_optional_services = []
    for stack in STACKS:
        config = _compose_config(root, stack, environment)
        project = config.get("name")
        if project != stack:
            raise DesiredHalt(
                f"Compose project identity drift for {stack}: rendered {project!r}"
            )
        for service_name, service in sorted(config.get("services", {}).items()):
            item = _service_projection(root, stack, project, service_name, service, provenance)
            if stack in PROTECTED_STACKS:
                protected_services.append(item)
            elif service_name == "docs-indexer":
                declared_optional_services.append(item)
            else:
                services.append(item)
    desired = {
        "schema": "kepler-collision-desired-v1",
        "servarr_commit": commit,
        "secretspec_project": "kepler",
        "source_sha256": {
            path.name: hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(files)
        },
        "stacks": list(MIGRATION_STACKS),
        "services": sorted(services, key=lambda item: (item["project"], item["service"])),
        "protected_services": protected_services,
        "declared_optional_services": declared_optional_services,
        "local_images": provenance["local_images"],
        "model_artifacts": _record_model_identities(provenance, model_identities),
        "legacy_images": provenance["legacy_images"],
        "legacy_mounts": provenance["legacy_mounts"],
    }
    rendered = canonical(desired)
    if DUMMY_PREFIX.encode() in rendered:
        raise DesiredHalt("synthetic environment marker escaped into desired state")
    return {
        "desired": desired,
        "desired_sha256": hashlib.sha256(rendered).hexdigest(),
        "schema": "kepler-collision-desired-v1",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--servarr-root", required=True)
    parser.add_argument("--expected-commit", default=SERVARR_COMMIT)
    parser.add_argument("--model-identities")
    args = parser.parse_args(argv)
    try:
        identities = None
        if args.model_identities:
            identities = json.loads(pathlib.Path(args.model_identities).read_text(encoding="utf-8"))
        print(json.dumps(generate(args.servarr_root, args.expected_commit, identities), sort_keys=True))
    except (DesiredHalt, OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"desired-state halted: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
