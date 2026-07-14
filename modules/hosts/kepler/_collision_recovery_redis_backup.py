#!/usr/bin/env python3
"""Render a deterministic, value-free Kepler K1 Redis backup evidence plan."""

import argparse
import hashlib
import json
import pathlib
import re
import sys


class RedisBackupHalt(Exception):
    """Inventory cannot safely produce Redis backup evidence."""


HEX64 = re.compile(r"[0-9a-f]{64}")
PROJECT_LABEL = "com.docker.compose.project"
SOURCE_VOLUME = "homelab_redis_data"
TARGET_VOLUME = "infra_redis_data"
SOURCE_PROJECT = "homelab"
TARGET_PROJECT = "infra"
SNAPSHOT_BOUNDARY = "/fast"
ACTIVE_STATES = {"paused", "restarting", "running"}


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def _bound_inventory(envelope, expected):
    if not isinstance(envelope, dict) or envelope.get("schema") != "kepler-collision-inventory-v1":
        raise RedisBackupHalt("invalid inventory envelope schema")
    inventory = envelope.get("inventory")
    claimed = str(envelope.get("inventory_sha256", ""))
    if not isinstance(inventory, dict) or not HEX64.fullmatch(claimed):
        raise RedisBackupHalt("invalid inventory envelope binding")
    if digest(inventory) != claimed:
        raise RedisBackupHalt("inventory envelope SHA-256 mismatch")
    if not HEX64.fullmatch(str(expected)) or expected != claimed:
        raise RedisBackupHalt("inventory drift: approval binding does not match")
    return inventory, claimed


def _exact_volume(inventory, name, project):
    volumes = inventory.get("volumes", [])
    if not isinstance(volumes, list):
        raise RedisBackupHalt("invalid inventory volumes")
    matches = [item for item in volumes if isinstance(item, dict) and item.get("name") == name]
    if len(matches) != 1:
        raise RedisBackupHalt(f"expected exactly one {name} volume")
    volume = matches[0]
    labels = volume.get("labels", {})
    if not isinstance(labels, dict) or labels.get(PROJECT_LABEL) != project:
        subject = "source" if name == SOURCE_VOLUME else "target"
        raise RedisBackupHalt(f"{subject} volume ownership mismatch")
    if volume.get("driver") != "local" or not isinstance(volume.get("mountpoint"), str) or not volume["mountpoint"]:
        raise RedisBackupHalt(f"invalid {name} physical identity")
    return volume


def _source_container(inventory, source, inventory_sha256, quiesce_approval):
    containers = inventory.get("containers", [])
    if not isinstance(containers, list):
        raise RedisBackupHalt("invalid inventory containers")
    matches = [
        item for item in containers
        if isinstance(item, dict)
        and item.get("name") == "redis"
        and item.get("labels", {}).get(PROJECT_LABEL) == SOURCE_PROJECT
        and item.get("labels", {}).get("com.docker.compose.service") == "redis"
    ]
    if len(matches) != 1:
        raise RedisBackupHalt("expected exactly one legacy Redis source container")
    container = matches[0]
    if not HEX64.fullmatch(str(container.get("id", ""))):
        raise RedisBackupHalt("invalid Redis source container ID")
    mounts = container.get("mounts", [])
    expected_mount = {
        "destination": "/data",
        "name": SOURCE_VOLUME,
        "read_only": False,
        "source": source["mountpoint"],
        "type": "volume",
    }
    if not isinstance(mounts, list) or mounts != [expected_mount]:
        raise RedisBackupHalt("Redis source mount mismatch")
    state = container.get("state")
    if not isinstance(state, str) or not state:
        raise RedisBackupHalt("invalid Redis source state")
    approval_sha256 = None
    if state in ACTIVE_STATES:
        approval_sha256 = _quiesce_approval(
            quiesce_approval, inventory_sha256, container
        )
    elif state != "exited":
        raise RedisBackupHalt("Redis source state must be exactly exited without quiesce")
    return container, approval_sha256


def _quiesce_approval(envelope, inventory_sha256, container):
    if not isinstance(envelope, dict) or envelope.get("schema") != "kepler-collision-quiesce-approval-v1":
        raise RedisBackupHalt("running Redis requires approved quiesce binding")
    approval = envelope.get("approval")
    claimed = str(envelope.get("approval_sha256", ""))
    if not isinstance(approval, dict) or not HEX64.fullmatch(claimed) or digest(approval) != claimed:
        raise RedisBackupHalt("invalid quiesce approval binding")
    if approval.get("inventory_sha256") != inventory_sha256:
        raise RedisBackupHalt("quiesce approval inventory binding mismatch")
    expected = [{"id": container["id"], "name": container["name"]}]
    if approval.get("containers") != expected:
        raise RedisBackupHalt("quiesce approval container binding mismatch")
    quiesce = approval.get("quiesce_manifest")
    if not isinstance(quiesce, dict) or quiesce.get("schema") != "kepler-collision-quiesce-manifest-v1":
        raise RedisBackupHalt("invalid quiesce manifest envelope schema")
    manifest = quiesce.get("manifest")
    manifest_sha256 = str(quiesce.get("manifest_sha256", ""))
    if not isinstance(manifest, dict) or not HEX64.fullmatch(manifest_sha256) or digest(manifest) != manifest_sha256:
        raise RedisBackupHalt("quiesce manifest envelope SHA-256 mismatch")
    if (
        quiesce.get("inventory_sha256") != inventory_sha256
        or manifest.get("inventory_sha256") != inventory_sha256
        or manifest.get("status") != "ready-for-separate-hash-bound-approval"
        or manifest.get("mode") != "dry-run-only"
    ):
        raise RedisBackupHalt("quiesce manifest inventory binding mismatch")
    stacks = manifest.get("stacks", [])
    if not isinstance(stacks, list):
        raise RedisBackupHalt("invalid quiesce manifest stacks")
    redis_stacks = [
        item for item in stacks
        if isinstance(item, dict) and container["name"] in item.get("containers", [])
    ]
    if not redis_stacks:
        raise RedisBackupHalt("quiesce manifest does not include Redis")
    if len(redis_stacks) != 1 or redis_stacks[0].get("stack") != "infra":
        raise RedisBackupHalt("quiesce manifest Redis must belong to infra stack")
    return claimed


def plan(inventory_envelope, expected_inventory_sha256, quiesce_approval=None):
    inventory, inventory_sha256 = _bound_inventory(
        inventory_envelope, expected_inventory_sha256
    )
    source = _exact_volume(inventory, SOURCE_VOLUME, SOURCE_PROJECT)
    target = _exact_volume(inventory, TARGET_VOLUME, TARGET_PROJECT)
    source_container, quiesce_approval_sha256 = _source_container(
        inventory, source, inventory_sha256, quiesce_approval
    )
    source_path = pathlib.PurePosixPath(source["mountpoint"])
    boundary = pathlib.PurePosixPath(SNAPSHOT_BOUNDARY)
    if source_path == boundary or boundary in source_path.parents:
        raise RedisBackupHalt("source volume is already inside snapshot boundary")

    datasets = inventory.get("datasets", [])
    if not isinstance(datasets, list) or sum(
        isinstance(item, dict) and item.get("mountpoint") == SNAPSHOT_BOUNDARY
        for item in datasets
    ) != 1:
        raise RedisBackupHalt("exact /fast snapshot boundary is unavailable")
    references = inventory.get("references", {}).get("volumes", {})
    if not isinstance(references, dict) or references.get(SOURCE_VOLUME) != ["redis"]:
        raise RedisBackupHalt("legacy Redis volume reference mismatch")
    target_references = references.get(TARGET_VOLUME, [])
    if not isinstance(target_references, list):
        raise RedisBackupHalt("invalid declared target references")

    root = f"{SNAPSHOT_BOUNDARY}/backups/kepler-collision-k1/redis/{inventory_sha256}"
    backup = f"{root}/dump.rdb"
    checksum = f"{backup}.sha256"
    comparison = f"{root}/restore-compare.json"
    disposable = f"kepler-k1-redis-restore-{inventory_sha256[:12]}"
    action_specs = (
        ("force-save", f"just kepler-recovery-redis-force-save {inventory_sha256}"),
        ("copy-backup", f"just kepler-recovery-redis-copy-backup {inventory_sha256} {backup}"),
        ("sha256", f"just kepler-recovery-sha256 {backup} {checksum}"),
        ("create-disposable-restore", f"just kepler-recovery-redis-restore-create {inventory_sha256} {disposable}"),
        ("restore-backup", f"just kepler-recovery-redis-restore-load {inventory_sha256} {disposable} {backup}"),
        ("compare-logical-digest", f"just kepler-recovery-redis-compare {inventory_sha256} {disposable} {comparison}"),
        ("remove-disposable-restore", f"just kepler-recovery-redis-restore-remove {inventory_sha256} {disposable}"),
    )
    manifest = {
        "abort_boundary": "before-any-action-on-inventory-drift-or-failed-precondition",
        "actions": [
            {"command": command, "kind": kind, "requires_previous_success": index > 0}
            for index, (kind, command) in enumerate(action_specs)
        ],
        "backup_artifact": backup,
        "checksum_artifact": checksum,
        "comparison_artifact": comparison,
        "declared_target_volume": {
            "name": target["name"],
            "owner_project": target["labels"][PROJECT_LABEL],
        },
        "disposable_restore_volume": disposable,
        "execution_supported": False,
        "inventory_sha256": inventory_sha256,
        "mode": "dry-run-only",
        "postcondition": "logical-digest-match-and-backup-checksum-recorded-before-source-retirement",
        "rollback_boundary": "source-volume-remains-authoritative-until-verified-restore-compare",
        "quiesce_approval_sha256": quiesce_approval_sha256,
        "snapshot_boundary": SNAPSHOT_BOUNDARY,
        "source_container": {
            "id": source_container["id"],
            "mount_destination": "/data",
            "name": source_container["name"],
            "project": source_container["labels"][PROJECT_LABEL],
            "service": source_container["labels"]["com.docker.compose.service"],
            "state": source_container["state"],
        },
        "source_volume": {
            "driver": source["driver"],
            "mountpoint": source["mountpoint"],
            "name": source["name"],
            "owner_project": source["labels"][PROJECT_LABEL],
            "references": references[SOURCE_VOLUME],
        },
        "status": "ready-for-separate-hash-bound-approval",
        "target_existing_references": sorted(target_references),
    }
    return {
        "inventory_sha256": inventory_sha256,
        "manifest": manifest,
        "manifest_sha256": digest(manifest),
        "schema": "kepler-collision-redis-backup-evidence-v1",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--expected-inventory-sha256", required=True)
    parser.add_argument("--quiesce-approval")
    args = parser.parse_args(argv)
    try:
        with open(args.inventory, encoding="utf-8") as handle:
            inventory = json.load(handle)
        approval = None
        if args.quiesce_approval:
            with open(args.quiesce_approval, encoding="utf-8") as handle:
                approval = json.load(handle)
        result = plan(inventory, args.expected_inventory_sha256, approval)
    except (OSError, json.JSONDecodeError, RedisBackupHalt) as error:
        print(f"Redis backup evidence halted: {error}", file=sys.stderr)
        return 2
    json.dump(result, sys.stdout, sort_keys=True, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
