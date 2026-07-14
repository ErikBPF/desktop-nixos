#!/usr/bin/env python3
"""Reconcile value-free Kepler K1 inventory and desired-state envelopes."""

import argparse
import hashlib
import json
import pathlib
import re
import sys


class ReconcileHalt(Exception):
    pass


HEX64 = re.compile(r"[0-9a-f]{64}")
GIT_COMMIT = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")
COMPOSE_PROJECT = "com.docker.compose.project"
COMPOSE_SERVICE = "com.docker.compose.service"
PROTECTED_NAMES = {"restate"}
PROTECTED_VOLUMES = {"restate_data"}
RETIRED_ALLOWLIST = {"gitlab", "airflow"}


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def _require_envelope(envelope, kind):
    payload_key = kind
    hash_key = f"{kind}_sha256"
    schema = f"kepler-collision-{kind}-v1"
    if not isinstance(envelope, dict) or envelope.get("schema", schema) != schema:
        raise ReconcileHalt(f"invalid {kind} envelope schema")
    if payload_key not in envelope or not HEX64.fullmatch(str(envelope.get(hash_key, ""))):
        raise ReconcileHalt(f"invalid {kind} envelope binding")
    if digest(envelope[payload_key]) != envelope[hash_key]:
        raise ReconcileHalt(f"{kind} envelope SHA-256 mismatch")
    return envelope[payload_key]


def _mount_identity(mount):
    return {
        "source": mount.get("source", ""),
        "target": mount.get("target", mount.get("destination", "")),
        "type": mount.get("type", "volume" if mount.get("name") else "bind"),
    }


def _diff(expected, actual):
    fields = []
    for field in ("labels", "mounts", "networks"):
        if expected[field] != actual[field]:
            fields.append({"actual": actual[field], "expected": expected[field], "field": field})
    return fields


def _covered(source, datasets, volumes):
    if source in volumes:
        source = volumes[source]
    if not source.startswith("/"):
        return False
    source_path = pathlib.PurePosixPath(source)
    return any(
        source_path == mount or mount in source_path.parents
        for mount in datasets if str(mount).startswith("/")
    )


def reconcile(inventory_envelope, desired_envelope, source_commits):
    inventory = _require_envelope(inventory_envelope, "inventory")
    desired = _require_envelope(desired_envelope, "desired")
    if not isinstance(source_commits, dict) or not source_commits or any(
        not name or not GIT_COMMIT.fullmatch(str(commit)) for name, commit in source_commits.items()
    ):
        raise ReconcileHalt("source commits must be a non-empty name-to-full-object-ID map")

    desired_by_name = {item["container_name"]: item for item in desired.get("services", [])}
    if len(desired_by_name) != len(desired.get("services", [])):
        raise ReconcileHalt("duplicate desired container_name")
    datasets = [pathlib.PurePosixPath(item["mountpoint"]) for item in inventory.get("datasets", [])]
    volumes = {item["name"]: item.get("mountpoint", "") for item in inventory.get("volumes", [])}
    classifications = []
    provenance_gaps = []
    coverage_gaps = []

    for container in inventory.get("containers", []):
        name = container.get("name", "")
        desired_item = desired_by_name.get(name)
        protected = name in PROTECTED_NAMES
        if desired_item is None:
            classifications.append({
                "action": "none", "classification": "protected" if protected else "noncollision",
                "container": name, "field_diffs": [],
                "reason": "restate-protected" if protected else "not-declared-by-desired-state",
            })
            continue
        expected = {
            "labels": desired_item["required_labels"],
            "mounts": sorted((_mount_identity(item) for item in desired_item.get("mounts", [])), key=canonical),
            "networks": sorted(desired_item.get("networks", [])),
        }
        actual = {
            "labels": {key: container.get("labels", {}).get(key, "") for key in (COMPOSE_PROJECT, COMPOSE_SERVICE)},
            "mounts": sorted((_mount_identity(item) for item in container.get("mounts", [])), key=canonical),
            "networks": sorted(container.get("networks", [])),
        }
        diffs = _diff(expected, actual)
        state = container.get("state", "")
        if state in {"running", "paused", "restarting"}:
            status = ("halt", "running-collision")
        elif not actual["labels"][COMPOSE_PROJECT] or not actual["labels"][COMPOSE_SERVICE]:
            status = ("halt", "missing-compose-labels")
        elif actual["labels"][COMPOSE_PROJECT] != desired_item["project"]:
            status = ("halt", "foreign-compose-project")
        elif actual["labels"][COMPOSE_SERVICE] != desired_item["service"]:
            status = ("halt", "foreign-compose-service")
        elif diffs:
            status = ("halt", "declared-runtime-mismatch")
        elif protected:
            status = ("none", "restate-protected")
        else:
            status = ("migrate", "stopped-declared-collision")
        classifications.append({"action": status[0], "classification": "halt" if status[0] == "halt" else ("protected" if protected else "declared-migrate"), "container": name, "field_diffs": diffs, "reason": status[1]})

        digest_status = desired_item.get("digest_status", "")
        if digest_status == "local-provenance-required":
            provenance_gaps.append({"container": name, "reason": "local-image-or-model-provenance-required"})
        elif digest_status != "immutable-registry-digest" or not container.get("image_digest"):
            provenance_gaps.append({"container": name, "reason": "immutable-registry-digest-required"})
        for mount in desired_item.get("mounts", []):
            source = mount.get("source", "")
            if source and not _covered(source, datasets, volumes):
                coverage_gaps.append({"container": name, "source": source, "reason": "persistent-mount-outside-snapshot-boundary"})

    selected_retired = sorted(
        name for name in RETIRED_ALLOWLIST
        if any(container.get("name", "").lower() == name for container in inventory.get("containers", []))
    )
    halt_reasons = sorted({item["reason"] for item in classifications if item["action"] == "halt"} | {item["reason"] for item in provenance_gaps} | {item["reason"] for item in coverage_gaps})
    manifest = {
        "classifications": sorted(classifications, key=lambda item: item["container"]),
        "desired_sha256": desired_envelope["desired_sha256"],
        "halt_reasons": halt_reasons,
        "inventory_sha256": inventory_envelope["inventory_sha256"],
        "persistent_coverage_gaps": sorted(coverage_gaps, key=canonical),
        "protected": {"containers": sorted(PROTECTED_NAMES), "volumes": sorted(PROTECTED_VOLUMES)},
        "provenance_gaps": sorted(provenance_gaps, key=canonical),
        "retired_allowlist": sorted(RETIRED_ALLOWLIST),
        "selected_retired": selected_retired,
        "source_commits": dict(sorted(source_commits.items())),
        "status": "halt" if halt_reasons else "ready",
    }
    return {"manifest": manifest, "manifest_sha256": digest(manifest), "schema": "kepler-collision-reconcile-v1"}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--desired", required=True)
    parser.add_argument("--source-commit", action="append", default=[])
    args = parser.parse_args(argv)
    try:
        commits = dict(item.split("=", 1) for item in args.source_commit)
        with open(args.inventory, encoding="utf-8") as handle:
            inventory = json.load(handle)
        with open(args.desired, encoding="utf-8") as handle:
            desired = json.load(handle)
        print(json.dumps(reconcile(inventory, desired, commits), sort_keys=True, separators=(",", ":")))
    except (OSError, ValueError, json.JSONDecodeError, ReconcileHalt) as error:
        print(f"reconcile halted: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
