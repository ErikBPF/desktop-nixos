#!/usr/bin/env python3
"""Gate value-free PostgreSQL backup/restore evidence for Kepler K1."""

import argparse
import hashlib
import json
import re
import sys


class DatabaseEvidenceHalt(Exception):
    """Database evidence is incomplete, invalid, or stale."""


HEX64 = re.compile(r"[0-9a-f]{64}")
TIMESTAMP = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z")
SAFE_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_-]*")
EVIDENCE_SCHEMA = "kepler-collision-database-evidence-v2"
INVENTORY_SCHEMA = "kepler-collision-inventory-v1"


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def _valid_name(value):
    return isinstance(value, str) and SAFE_NAME.fullmatch(value)


def _inventory_binding(envelope):
    if not isinstance(envelope, dict) or envelope.get("schema") != INVENTORY_SCHEMA:
        raise DatabaseEvidenceHalt("invalid inventory envelope schema")
    inventory = envelope.get("inventory")
    claimed = envelope.get("inventory_sha256")
    if not isinstance(inventory, dict) or not isinstance(claimed, str):
        raise DatabaseEvidenceHalt("invalid inventory envelope binding")
    if not HEX64.fullmatch(claimed) or digest(inventory) != claimed:
        raise DatabaseEvidenceHalt("inventory SHA-256 mismatch")
    return claimed, inventory


def _validate_retained(items):
    if not isinstance(items, list) or not items:
        raise DatabaseEvidenceHalt("retained database evidence is empty")
    result = []
    seen = set()
    for item in items:
        if not isinstance(item, dict):
            raise DatabaseEvidenceHalt("invalid retained database evidence")
        name, owner = item.get("name"), item.get("owner")
        if not _valid_name(name) or not _valid_name(owner):
            raise DatabaseEvidenceHalt("invalid retained database identity")
        if name == "airflow":
            raise DatabaseEvidenceHalt("Airflow must not be retained")
        if name in seen:
            raise DatabaseEvidenceHalt("duplicate retained database evidence")
        seen.add(name)
        if set(item) != {"name", "owner"}:
            raise DatabaseEvidenceHalt("invalid retained database identity fields")
        result.append({"name": name, "owner": owner})
    return sorted(result, key=lambda item: item["name"])


def _validate_cluster(artifact, restore, retained):
    if not isinstance(artifact, dict) or set(artifact) != {"bytes", "created_at", "sha256"}:
        raise DatabaseEvidenceHalt("invalid retained cluster artifact metadata")
    if (
        not isinstance(artifact["bytes"], int)
        or isinstance(artifact["bytes"], bool)
        or artifact["bytes"] <= 0
        or not isinstance(artifact["sha256"], str)
        or not HEX64.fullmatch(artifact["sha256"])
        or not isinstance(artifact["created_at"], str)
        or not TIMESTAMP.fullmatch(artifact["created_at"])
    ):
        raise DatabaseEvidenceHalt("invalid retained cluster artifact metadata")
    required = {"artifact_sha256", "database_inventory_sha256", "logical_sha256", "retained_databases", "status"}
    if not isinstance(restore, dict) or set(restore) != required:
        raise DatabaseEvidenceHalt("retained cluster restore verification failed")
    if restore["artifact_sha256"] != artifact["sha256"]:
        raise DatabaseEvidenceHalt("restore artifact binding mismatch")
    if any(not isinstance(restore[key], str) or not HEX64.fullmatch(restore[key]) for key in ("database_inventory_sha256", "logical_sha256")):
        raise DatabaseEvidenceHalt("invalid retained cluster logical evidence")
    if restore["status"] != "passed" or restore["retained_databases"] != [item["name"] for item in retained]:
        raise DatabaseEvidenceHalt("retained cluster restore verification failed")
    return dict(artifact), dict(restore)


def _validate_coverage(discovered, retained):
    if not isinstance(discovered, list) or not discovered:
        raise DatabaseEvidenceHalt("database inventory coverage is missing")
    identities = []
    for item in discovered:
        if (
            not isinstance(item, dict)
            or set(item) != {"name", "owner"}
            or not _valid_name(item["name"])
            or not _valid_name(item["owner"])
        ):
            raise DatabaseEvidenceHalt("invalid database inventory coverage")
        identities.append((item["name"], item["owner"]))
    if len(identities) != len(set(identities)):
        raise DatabaseEvidenceHalt("duplicate database inventory coverage")
    airflow = [item for item in identities if item[0] == "airflow"]
    retained_identities = sorted(item for item in identities if item[0] != "airflow")
    expected = sorted((item["name"], item["owner"]) for item in retained)
    if len(airflow) != 1 or retained_identities != expected:
        raise DatabaseEvidenceHalt("database inventory coverage mismatch")


def plan(inventory_envelope, evidence, expected_inventory_sha256):
    inventory_sha256, inventory = _inventory_binding(inventory_envelope)
    if not isinstance(expected_inventory_sha256, str) or not HEX64.fullmatch(
        expected_inventory_sha256
    ):
        raise DatabaseEvidenceHalt("invalid expected inventory SHA-256")
    if expected_inventory_sha256 != inventory_sha256:
        raise DatabaseEvidenceHalt("approval inventory drift")
    if not isinstance(evidence, dict) or evidence.get("schema") != EVIDENCE_SCHEMA:
        raise DatabaseEvidenceHalt("invalid database evidence schema")
    if evidence.get("inventory_sha256") != inventory_sha256:
        raise DatabaseEvidenceHalt("evidence inventory drift")
    postgres = [item for item in inventory.get("containers", []) if item.get("name") == "postgres"]
    if len(postgres) != 1 or evidence.get("source_container_id") != postgres[0].get("id"):
        raise DatabaseEvidenceHalt("PostgreSQL source container identity drift")
    captured_at = evidence.get("captured_at")
    if not isinstance(captured_at, str) or not TIMESTAMP.fullmatch(captured_at):
        raise DatabaseEvidenceHalt("invalid database evidence timestamp")
    if evidence.get("retired_databases") != ["airflow"]:
        raise DatabaseEvidenceHalt("retired database allowlist must be exactly Airflow")

    retained = _validate_retained(evidence.get("retained_databases"))
    database_inventory = evidence.get("database_inventory")
    _validate_coverage(database_inventory, retained)
    artifact, restore = _validate_cluster(evidence.get("cluster_artifact"), evidence.get("cluster_restore"), retained)
    if restore["database_inventory_sha256"] != digest(database_inventory):
        raise DatabaseEvidenceHalt("cluster restore database inventory binding mismatch")
    manifest = {
        "airflow_drop_gate": "eligible-after-separate-approved-retirement-manifest",
        "captured_at": captured_at,
        "commands": [
            "just kepler-recovery-postgres-backup <inventory-sha256>",
            "just kepler-recovery-postgres-restore-test <inventory-sha256>",
            "just kepler-recovery-airflow-retire <approved-retirement-manifest-sha256>",
        ],
        "execution_supported": False,
        "inventory_sha256": inventory_sha256,
        "mode": "dry-run-evidence-gate",
        "retained_databases": retained,
        "cluster_artifact": artifact,
        "cluster_restore": restore,
        "retired_databases": ["airflow"],
        "status": "retained-databases-verified",
    }
    return {
        "manifest": manifest,
        "manifest_sha256": digest(manifest),
        "schema": "kepler-collision-database-evidence-manifest-v1",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--evidence", required=True)
    parser.add_argument("--expected-inventory-sha256", required=True)
    args = parser.parse_args(argv)
    try:
        with open(args.inventory, encoding="utf-8") as handle:
            inventory = json.load(handle)
        with open(args.evidence, encoding="utf-8") as handle:
            evidence = json.load(handle)
        result = plan(inventory, evidence, args.expected_inventory_sha256)
    except (OSError, json.JSONDecodeError, DatabaseEvidenceHalt) as error:
        print(f"database evidence halted: {error}", file=sys.stderr)
        return 2
    json.dump(result, sys.stdout, sort_keys=True, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
