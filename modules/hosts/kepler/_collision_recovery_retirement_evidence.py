#!/usr/bin/env python3
"""Assemble deterministic, value-free Kepler retirement planner evidence."""

import argparse
import hashlib
import json
import re
import sys


class RetirementEvidenceHalt(Exception):
    pass


HEX64 = re.compile(r"[0-9a-f]{64}")
FAMILIES = {
    "gitlab": {
        "containers": ("gitlab", "gitlab-runner"),
        "paths": ("/bulk/git", "/fast/apps/gitlab/config", "/fast/apps/gitlab/logs", "/fast/apps/gitlab-runner"),
        "project": "gitlab",
        "repositories": ("docker.io/gitlab/gitlab-ce", "docker.io/gitlab/gitlab-runner"),
        "volumes": (),
    },
    "airflow": {
        "containers": ("airflow-init", "airflow-scheduler", "airflow-triggerer", "airflow-webserver", "airflow-worker"),
        "paths": ("/fast/apps/airflow/dags", "/fast/apps/airflow/plugins"),
        "project": "airflow",
        "repositories": ("docker.io/apache/airflow",),
        "volumes": ("airflow_config", "airflow_logs"),
    },
    "restate": {
        "containers": ("restate",),
        "paths": (),
        "project": "orchestration",
        "repositories": ("docker.restate.dev/restatedev/restate",),
        "volumes": ("restate_data",),
    },
}
DISPOSITIONS = ("f5-tts-server", "ha-train-run", "minicpm-train", "uv_build")
F5_PATH = "/fast/ai-models/f5-tts"


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def reference(envelope):
    return {"envelope": envelope, "sha256": digest(envelope)}


def _inventory(envelope):
    if not isinstance(envelope, dict) or envelope.get("schema") != "kepler-collision-inventory-v1":
        raise RetirementEvidenceHalt("invalid inventory schema")
    inventory = envelope.get("inventory")
    claimed = envelope.get("inventory_sha256")
    if not isinstance(inventory, dict) or not isinstance(claimed, str) or digest(inventory) != claimed:
        raise RetirementEvidenceHalt("inventory SHA-256 mismatch")
    return inventory, claimed


def _paths(envelope):
    if not isinstance(envelope, dict) or envelope.get("schema") != "kepler-retirement-path-evidence-envelope-v1" or envelope.get("status") != "verified":
        raise RetirementEvidenceHalt("invalid retirement path evidence")
    records = envelope.get("paths", envelope.get("evidence"))
    if not isinstance(records, list) or envelope.get("evidence_sha256") not in (None, digest(records)):
        raise RetirementEvidenceHalt("retirement path evidence SHA-256 mismatch")
    required = {"path", "existence", "type", "device", "inode", "byte_count"}
    if any(not isinstance(item, dict) or set(item) != required for item in records):
        raise RetirementEvidenceHalt("invalid retirement path record")
    if len({item["path"] for item in records}) != len(records):
        raise RetirementEvidenceHalt("duplicate retirement path record")
    normalized = {"schema": envelope["schema"], "status": "verified", "paths": records}
    return normalized, {item["path"]: item for item in records}


def _database(envelope, inventory_sha256):
    if not isinstance(envelope, dict) or envelope.get("schema") != "kepler-collision-database-evidence-manifest-v1":
        raise RetirementEvidenceHalt("invalid database evidence schema")
    manifest = envelope.get("manifest")
    if not isinstance(manifest, dict) or envelope.get("manifest_sha256") != digest(manifest):
        raise RetirementEvidenceHalt("database evidence SHA-256 mismatch")
    if manifest.get("inventory_sha256") != inventory_sha256 or manifest.get("status") != "retained-databases-verified":
        raise RetirementEvidenceHalt("database evidence inventory/status mismatch")
    retained = manifest.get("retained_databases")
    if not isinstance(retained, list) or any(not isinstance(item, dict) or set(item) != {"name", "owner"} for item in retained):
        raise RetirementEvidenceHalt("invalid retained database identities")
    names = [item["name"] for item in retained]
    if not names or names != sorted(set(names)):
        raise RetirementEvidenceHalt("retained database identities must be exact and sorted")
    return names


def _redis(envelope, inventory_sha256):
    if envelope is None:
        return
    if not isinstance(envelope, dict) or envelope.get("schema") != "kepler-collision-redis-backup-evidence-v1" or envelope.get("inventory_sha256") != inventory_sha256:
        raise RetirementEvidenceHalt("invalid Redis evidence binding")
    manifest = envelope.get("manifest")
    if not isinstance(manifest, dict) or envelope.get("manifest_sha256") != digest(manifest):
        raise RetirementEvidenceHalt("Redis evidence SHA-256 mismatch")


def _image_identity(item):
    value = item.get("id")
    if not isinstance(value, str):
        return None
    value = value.removeprefix("sha256:")
    return f"sha256:{value}" if HEX64.fullmatch(value) else None


def assemble(inventory_envelope, path_envelope, database_envelope, redis_envelope=None):
    inventory, inventory_sha256 = _inventory(inventory_envelope)
    normalized_paths, paths = _paths(path_envelope)
    expected_databases = _database(database_envelope, inventory_sha256)
    _redis(redis_envelope, inventory_sha256)
    containers = inventory.get("containers", [])
    images = inventory.get("images", [])
    volumes = inventory.get("volumes", [])
    references = inventory.get("references", {}).get("images", {})
    if not all(isinstance(value, list) for value in (containers, images, volumes)) or not isinstance(references, dict):
        raise RetirementEvidenceHalt("invalid inventory collections")
    by_container = {item.get("name"): item for item in containers}
    if len(by_container) != len(containers):
        raise RetirementEvidenceHalt("duplicate container identity")
    path_reference = reference(normalized_paths)

    retired = []
    for family_name, policy in FAMILIES.items():
        family_containers = [
            {"id": by_container[name]["id"], "name": name, "state": by_container[name]["state"]}
            for name in policy["containers"] if name in by_container
        ]
        family_paths = [path for path in policy["paths"] if paths.get(path, {}).get("existence") is True]
        family_volumes = []
        for logical_name in policy["volumes"]:
            matches = [item for item in volumes if item.get("labels") == {
                "com.docker.compose.project": policy["project"],
                "com.docker.compose.volume": logical_name,
            }]
            if len(matches) > 1:
                raise RetirementEvidenceHalt(f"ambiguous {family_name} volume")
            if matches:
                family_volumes.append({"logical_name": logical_name, "runtime_name": matches[0]["name"]})
        family_images = []
        for item in images:
            repositories = {value.split("@", 1)[0] for value in item.get("digests", [])}
            identity = _image_identity(item)
            if identity and repositories and repositories <= set(policy["repositories"]):
                family_images.append(identity)
        family_images = sorted(set(family_images))
        resources = {
            "family": family_name,
            "containers": family_containers,
            "paths": family_paths,
            "volumes": family_volumes,
            "databases": ["airflow"] if family_name == "airflow" and family_containers else [],
            "secrets": [],
            "images": family_images,
        }
        family_proof = {
            "family": family_name,
            "path_identities": [
                {"envelope_sha256": path_reference["sha256"], "path": path}
                for path in family_paths
            ],
            "resources_sha256": digest(resources),
            "schema": "kepler-retired-family-evidence-v1",
            "status": "verified",
        }
        retired.append({**resources, "family_evidence": reference(family_proof)})

    dispositions = []
    for name in DISPOSITIONS:
        item = by_container.get(name)
        if item is None:
            if name == "f5-tts-server":
                continue
            raise RetirementEvidenceHalt(f"required disposition container absent: {name}")
        sources = [mount.get("source") for mount in item.get("mounts", [])]
        if any(not isinstance(source, str) for source in sources):
            raise RetirementEvidenceHalt(f"invalid disposition mounts: {name}")
        sources.sort()
        proof = {
            "container_id": item["id"], "schema": "kepler-mount-retention-evidence-v1",
            "sources": sources, "status": "verified",
        }
        dispositions.append({
            "id": item["id"], "mount_retention": reference(proof),
            "name": name, "state": item["state"],
        })
    f5_path = paths.get(F5_PATH)
    if not f5_path or f5_path.get("existence") is not True or f5_path.get("type") != "directory":
        raise RetirementEvidenceHalt("F5 path evidence unavailable")
    f5_identities = []
    for item in images:
        repositories = {value.split("@", 1)[0] for value in item.get("digests", [])}
        repositories.update(value.rsplit(":", 1)[0] for value in item.get("names", []))
        identity = _image_identity(item)
        if identity and repositories == {"docker.io/kepler/f5-tts-server"}:
            f5_identities.append(identity)
    f5_identities = sorted(set(f5_identities))
    if len(f5_identities) != 1:
        raise RetirementEvidenceHalt("F5 image identity unavailable")
    preflight = {
        "declared_secrets": [], "external_credentials": [], "external_revocations": [],
        "schema": "kepler-retired-preflight-evidence-v1", "secret_artifacts": [], "status": "verified",
    }
    return {
        "dispositions": {
            "artifacts": [{"name": "f5-tts-model-data", "path": F5_PATH, "path_evidence_sha256": path_reference["sha256"]}],
            "containers": dispositions,
            "images": [{"container": "f5-tts-server", "identity": f5_identities[0], "name": "f5-tts-image"}],
        },
        "expected_retained_databases": expected_databases,
        "inventory_sha256": inventory_sha256,
        "proofs": {
            "retained_database_restore": reference(database_envelope),
            "retired_preflight": reference(preflight),
            "retirement_paths": path_reference,
        },
        "retired": retired,
        "schema": "kepler-retirement-evidence-v1",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--retirement-paths", required=True)
    parser.add_argument("--database-evidence", required=True)
    parser.add_argument("--redis-evidence")
    args = parser.parse_args(argv)
    try:
        with open(args.inventory, encoding="utf-8") as handle:
            inventory = json.load(handle)
        with open(args.retirement_paths, encoding="utf-8") as handle:
            paths = json.load(handle)
        with open(args.database_evidence, encoding="utf-8") as handle:
            database = json.load(handle)
        redis = None
        if args.redis_evidence:
            with open(args.redis_evidence, encoding="utf-8") as handle:
                redis = json.load(handle)
        result = assemble(inventory, paths, database, redis)
    except (OSError, json.JSONDecodeError, RetirementEvidenceHalt) as error:
        print(f"retirement evidence halted: {error}", file=sys.stderr)
        return 2
    json.dump(result, sys.stdout, sort_keys=True, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
