#!/usr/bin/env python3
"""Pure, value-free K0 planner. It never contacts a host or executes actions."""

import argparse
import hashlib
import json
import re
import sys


class PlanHalt(Exception):
    pass


class InventoryDrift(Exception):
    pass


POLICY = {
    "retired_services": ["gitlab", "airflow", "restate"],
    "gitlab_containers": ["gitlab", "gitlab-runner"],
    "airflow_containers": [
        "airflow-webserver",
        "airflow-scheduler",
        "airflow-triggerer",
        "airflow-worker",
        "airflow-init",
    ],
    "restate_containers": ["restate"],
    "retired_image_repositories": {
        "gitlab": "docker.io/gitlab/gitlab-ce",
        "gitlab-runner": "docker.io/gitlab/gitlab-runner",
        "airflow-webserver": "docker.io/apache/airflow",
        "airflow-scheduler": "docker.io/apache/airflow",
        "airflow-triggerer": "docker.io/apache/airflow",
        "airflow-worker": "docker.io/apache/airflow",
        "airflow-init": "docker.io/apache/airflow",
        "restate": "docker.io/restatedev/restate",
    },
    "gitlab_paths": [
        "/fast/apps/gitlab/config",
        "/fast/apps/gitlab/logs",
        "/fast/apps/gitlab-runner",
        "/bulk/git",
    ],
    "airflow_paths": [
        "/fast/apps/airflow/dags",
        "/fast/apps/airflow/plugins",
    ],
    "airflow_volumes": ["airflow_logs", "airflow_config"],
    "airflow_databases": ["airflow"],
    "restate_paths": [],
    "restate_volumes": ["restate_data"],
    "restate_databases": [],
    "retired_secrets": [
        "GITLAB_RUNNER_TOKEN",
        "POSTGRES_DB_AIRFLOW",
        "AIRFLOW_FERNET_KEY",
        "AIRFLOW_SECRET_KEY",
        "AIRFLOW_ADMIN_PASSWORD",
    ],
    "gitlab_secrets": ["GITLAB_RUNNER_TOKEN"],
    "airflow_secrets": [
        "POSTGRES_DB_AIRFLOW", "AIRFLOW_FERNET_KEY", "AIRFLOW_SECRET_KEY",
        "AIRFLOW_ADMIN_PASSWORD",
    ],
    "restate_secrets": [],
}

MIGRATION_ORDER = ["infra", "docs-search"]
PHASE_ORDER = [
    "inventory",
    "classify",
    "retained-database-backup-restore",
    "retired-secret-and-artifact-preflight",
    "retirement",
    "retained-state-protection",
    *MIGRATION_ORDER,
    "reboot-validation",
    "retention",
]
REGISTRY_DIGEST = re.compile(r"@sha256:[0-9a-f]{64}$")
SHA256 = re.compile(r"(?:sha256:)?[0-9a-f]{64}$")
COMMIT = re.compile(r"[0-9a-f]{40,64}$")
GATE_ORDER = [
    "inventory_collection",
    "classification",
    "retained_database_backup_restore",
    "retired_secret_revocation",
    "mixed_backup_sanitization",
    "exact_artifact_selection",
    "postgres_checkpoint",
    "redis_disposable_reset",
    "qdrant_idle",
    "minio_idle",
    "persistent_mount_coverage",
    "zfs_snapshot",
    "replacement_start",
    "replacement_validation",
    "reboot_validation",
    "cleanup_manifest_match",
]
SCHEMA = {
    "inventory": {"containers", "local_artifacts", "persistent_mounts", "completed", "gates", "image_references", "redis_reset"},
    "container": {
        "name", "collision", "state", "project", "labels_complete", "mounts",
        "desired_mounts", "image", "retired_kind", "image_service_specific",
        "volumes", "databases", "secrets",
    },
    "persistent_mount": {"source", "snapshot_covered", "backup_verified"},
    "completion": {"resource", "evidence_sha256", "final_state"},
    "image_artifact": {"kind", "name", "image_id", "source_commit", "build_inputs_sha256"},
    "model_artifact": {"kind", "name", "model_sha256", "version"},
    "redis_reset": {
        "container_id", "container_name", "container_state", "project", "service",
        "volume_driver", "volume_mountpoint", "volume_name", "volume_references",
    },
}


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def inventory_hash(inventory):
    return hashlib.sha256(canonical(inventory)).hexdigest()


def manifest_hash(manifest):
    return hashlib.sha256(canonical(manifest)).hexdigest()


def _retired_kind(name):
    if name in POLICY["gitlab_containers"]:
        return "gitlab"
    if name in POLICY["airflow_containers"]:
        return "airflow"
    if name in POLICY["restate_containers"]:
        return "restate"
    return None


def _exact_keys(value, allowed, path):
    if not isinstance(value, dict):
        raise PlanHalt(f"object required: {path}")
    unknown = set(value) - allowed
    if unknown:
        raise PlanHalt(f"unknown field forbidden: {path}.{sorted(unknown)[0]}")


def _validate_schema(inventory):
    _exact_keys(inventory, SCHEMA["inventory"], "inventory")
    for index, container in enumerate(inventory.get("containers", [])):
        _exact_keys(container, SCHEMA["container"], f"inventory.containers[{index}]")
        if not isinstance(container.get("collision"), bool):
            raise PlanHalt("container collision must be boolean")
    for index, mount in enumerate(inventory.get("persistent_mounts", [])):
        _exact_keys(mount, SCHEMA["persistent_mount"], f"inventory.persistent_mounts[{index}]")
    for index, completion in enumerate(inventory.get("completed", [])):
        _exact_keys(completion, SCHEMA["completion"], f"inventory.completed[{index}]")
    for index, artifact in enumerate(inventory.get("local_artifacts", [])):
        kind = artifact.get("kind")
        if kind not in {"image", "model"}:
            raise PlanHalt(f"unknown local artifact kind: {kind}")
        _exact_keys(artifact, SCHEMA[f"{kind}_artifact"], f"inventory.local_artifacts[{index}]")
    references = inventory.get("image_references", {})
    if not isinstance(references, dict) or any(
        not isinstance(image, str) or not isinstance(users, list) or any(not isinstance(user, str) for user in users)
        for image, users in references.items()
    ):
        raise PlanHalt("image_references must map image identities to resource-name lists")
    _exact_keys(inventory.get("redis_reset"), SCHEMA["redis_reset"], "inventory.redis_reset")


def _validate_redis_reset(item):
    expected = {
        "container_name": "redis",
        "container_state": "stopped",
        "project": "homelab",
        "service": "redis",
        "volume_driver": "local",
        "volume_mountpoint": "/home/erik/.local/share/containers/storage/volumes/homelab_redis_data/_data",
        "volume_name": "homelab_redis_data",
        "volume_references": ["redis"],
    }
    if not SHA256.fullmatch(str(item.get("container_id", ""))):
        raise PlanHalt("invalid disposable Redis container identity")
    for field, value in expected.items():
        if item.get(field) != value:
            raise PlanHalt(f"disposable Redis reset mismatch: {field}")
    return {
        "container": {
            "id": item["container_id"],
            "name": item["container_name"],
            "state": item["container_state"],
        },
        "mode": "dry-run",
        "next": "declarative-infra-recreates-desired-redis",
        "project": item["project"],
        "service": item["service"],
        "volume": {
            "driver": item["volume_driver"],
            "mountpoint": item["volume_mountpoint"],
            "name": item["volume_name"],
            "references": item["volume_references"],
        },
    }


def _validate_identities(inventory):
    for container in inventory.get("containers", []):
        image = container.get("image", "")
        if not REGISTRY_DIGEST.search(image):
            raise PlanHalt(f"immutable registry digest missing: {container.get('name', '<unknown>')}")
    for artifact in inventory.get("local_artifacts", []):
        if artifact["kind"] == "image":
            if not SHA256.fullmatch(artifact.get("image_id", "")):
                raise PlanHalt("invalid local image identity")
            if not COMMIT.fullmatch(artifact.get("source_commit", "")):
                raise PlanHalt("invalid source commit")
            if not SHA256.fullmatch(artifact.get("build_inputs_sha256", "")):
                raise PlanHalt("invalid build inputs identity")
        elif not SHA256.fullmatch(artifact.get("model_sha256", "")) or not artifact.get("version"):
            raise PlanHalt("invalid model identity")


def _validate_mount_coverage(inventory):
    for mount in inventory.get("persistent_mounts", []):
        if not (mount.get("snapshot_covered") or mount.get("backup_verified")):
            raise PlanHalt(f"unprotected persistent mount: {mount.get('source', '<unknown>')}")


def _validate_gates(inventory):
    gates = inventory.get("gates", {})
    if set(gates) != set(GATE_ORDER) or any(not isinstance(result, bool) for result in gates.values()):
        raise PlanHalt("every phase gate must be explicitly declared boolean")


def _mount_sources(container):
    return [mount.split(":", 1)[0] for mount in container.get("mounts", [])]


def _validate_retired(container, retired):
    name = container.get("name", "")
    if container.get("retired_kind") != retired or container.get("project") != retired:
        raise PlanHalt(f"retired ownership metadata mismatch: {name}")
    if container.get("state") == "running" or not container.get("labels_complete"):
        raise PlanHalt(f"unsafe retired collision: {name}")
    expected_paths = set(POLICY[f"{retired}_paths"])
    if set(_mount_sources(container)) != expected_paths:
        raise PlanHalt(f"retired mount selection not exact: {name}")
    expected_volumes = set(POLICY.get(f"{retired}_volumes", []))
    if set(container.get("volumes", [])) != expected_volumes:
        raise PlanHalt(f"retired volume selection not exact: {name}")
    expected_databases = set(POLICY.get(f"{retired}_databases", []))
    if set(container.get("databases", [])) != expected_databases:
        raise PlanHalt(f"retired database selection not exact: {name}")
    expected_secrets = set(POLICY[f"{retired}_secrets"])
    if set(container.get("secrets", [])) != expected_secrets:
        raise PlanHalt(f"retired secret selection not exact: {name}")
    if not container.get("image_service_specific"):
        raise PlanHalt(f"retired image ownership unproven: {name}")
    repository = container.get("image", "").split(":", 1)[0]
    if repository != POLICY["retired_image_repositories"][name]:
        raise PlanHalt(f"retired image repository mismatch: {name}")


def _classify(container):
    name = container.get("name", "")
    if not container["collision"]:
        if container.get("state") != "running" or not container.get("labels_complete"):
            raise PlanHalt(f"unhealthy non-collision resource: {name}")
        return "noncollision"
    retired = _retired_kind(name)
    if retired:
        _validate_retired(container, retired)
        return "retired-wipe"
    if container.get("retired_kind") in POLICY["retired_services"]:
        raise PlanHalt(f"retired container name outside exact allowlist: {name}")
    if container.get("state") == "running":
        raise PlanHalt(f"running collision: {name}")
    if not container.get("labels_complete"):
        raise PlanHalt(f"missing Compose labels: {name}")
    project = container.get("project")
    if project not in MIGRATION_ORDER:
        raise PlanHalt(f"foreign or unknown project: {name}")
    if container.get("mounts") != container.get("desired_mounts"):
        raise PlanHalt(f"mount mismatch: {name}")
    return "declared-migrate"


def plan(inventory):
    _validate_schema(inventory)
    _validate_gates(inventory)
    _validate_identities(inventory)
    _validate_mount_coverage(inventory)
    redis_reset = _validate_redis_reset(inventory["redis_reset"])
    completed = {}
    for record in inventory.get("completed", []):
        expected_state = "retired-absent" if _retired_kind(record["resource"]) else "replacement-validated"
        if not SHA256.fullmatch(record.get("evidence_sha256", "")) or record.get("final_state") != expected_state:
            raise PlanHalt(f"invalid completion evidence: {record.get('resource', '<unknown>')}")
        completed[record["resource"]] = record
    image_users = {}
    for container in inventory.get("containers", []):
        image_users.setdefault(container["image"], set()).add(container["name"])
    for image, users in inventory.get("image_references", {}).items():
        image_users.setdefault(image, set()).update(users)

    resources = []
    actions = []
    for container in sorted(inventory.get("containers", []), key=lambda item: item["name"]):
        classification = _classify(container)
        resource = {"name": container["name"], "classification": classification}
        if classification == "retired-wipe":
            resource["retired_kind"] = _retired_kind(container["name"])
            resource["image_action"] = (
                "protected-shared" if len(image_users[container["image"]]) > 1 else "exact-retired-only"
            )
            resource["selected"] = {
                "paths": sorted(_mount_sources(container)),
                "volumes": sorted(container["volumes"]),
                "databases": sorted(container["databases"]),
                "secrets": sorted(container["secrets"]),
                "image": container["image"],
            }
        resources.append(resource)
        if classification != "noncollision" and container["name"] not in completed:
            actions.append({
                "mode": "dry-run",
                "resource": container["name"],
                "classification": classification,
            })

    operations = []
    failed_gate = None
    for gate in GATE_ORDER:
        if inventory["gates"][gate]:
            operations.append({"phase": gate, "type": "preflight", "mode": "dry-run"})
        else:
            failed_gate = gate
            operations.append({
                "phase": gate,
                "type": "halt",
                "mode": "dry-run",
                "retain": ["quarantined-containers", "snapshots", "backups", "ledgers"],
            })
            actions = []
            break
    visible_resources = resources
    if failed_gate in {"inventory_collection", "classification"}:
        visible_resources = []
    return {
        "schema": "kepler-collision-plan-v1",
        "inventory_sha256": inventory_hash(inventory),
        "phase_order": PHASE_ORDER,
        "migration_order": MIGRATION_ORDER,
        "policy": POLICY,
        "resources": visible_resources,
        "status": "halt" if failed_gate else "ready",
        "failed_gate": failed_gate,
        "operations": operations,
        "actions": actions,
        "redis_reset": redis_reset,
        "retention": {
            "cleanup_eligible_days": 30,
            "cleanup": "separate-exact-resource-approval",
        },
    }


def verify_inventory(inventory, manifest):
    actual = inventory_hash(inventory)
    if actual != manifest.get("inventory_sha256"):
        raise InventoryDrift(f"inventory SHA-256 changed: expected {manifest.get('inventory_sha256')}, got {actual}")


def verify_envelope(inventory, envelope):
    manifest = envelope.get("manifest")
    if not isinstance(manifest, dict):
        raise InventoryDrift("manifest envelope missing manifest")
    expected = envelope.get("manifest_sha256")
    actual = manifest_hash(manifest)
    if expected != actual:
        raise InventoryDrift(f"manifest SHA-256 changed: expected {expected}, got {actual}")
    verify_inventory(inventory, manifest)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    plan_parser = subparsers.add_parser("plan", help="render a local fixture plan")
    plan_parser.add_argument("inventory")
    verify_parser = subparsers.add_parser("verify", help="verify inventory binding only")
    verify_parser.add_argument("inventory")
    verify_parser.add_argument("manifest")
    args = parser.parse_args(argv)
    try:
        with open(args.inventory, encoding="utf-8") as handle:
            inventory = json.load(handle)
        if args.command == "plan":
            manifest = plan(inventory)
            print(json.dumps({"manifest": manifest, "manifest_sha256": manifest_hash(manifest)}, sort_keys=True))
        else:
            with open(args.manifest, encoding="utf-8") as handle:
                envelope = json.load(handle)
            verify_envelope(inventory, envelope)
    except (OSError, json.JSONDecodeError, PlanHalt, InventoryDrift) as error:
        print(f"planner halted: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
