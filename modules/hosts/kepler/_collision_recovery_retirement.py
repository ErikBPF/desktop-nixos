#!/usr/bin/env python3
"""Render an exact, value-free retirement approval manifest. Never executes."""

import argparse
import hashlib
import json
import posixpath
import re
import sys


class RetirementHalt(Exception):
    pass


class RetirementDrift(Exception):
    pass


SHA256 = re.compile(r"(?:sha256:)?[0-9a-f]{64}$")
CONTAINER_ID = re.compile(r"[0-9a-f]{64}$")
F5_PATH = re.compile(
    r"/fast/ai-models/f5-tts/hf/models--firstpixel--F5-TTS-pt-br/"
    r"snapshots/[^/]+/pt-br/model_last\.safetensors$"
)
RETIRED_ALLOWLIST = {
    "gitlab": {
        "containers": ["gitlab", "gitlab-runner"],
        "paths": [
            "/bulk/git", "/fast/apps/gitlab/config", "/fast/apps/gitlab/logs",
            "/fast/apps/gitlab-runner",
        ],
        "volumes": [],
        "databases": [],
        "secrets": ["GITLAB_RUNNER_TOKEN"],
    },
    "airflow": {
        "containers": [
            "airflow-init", "airflow-scheduler", "airflow-triggerer",
            "airflow-webserver", "airflow-worker",
        ],
        "paths": ["/fast/apps/airflow/dags", "/fast/apps/airflow/plugins"],
        "volumes": ["airflow_config", "airflow_logs"],
        "databases": ["airflow"],
        "secrets": [
            "AIRFLOW_ADMIN_PASSWORD", "AIRFLOW_FERNET_KEY", "AIRFLOW_SECRET_KEY",
            "POSTGRES_DB_AIRFLOW",
        ],
    },
}
DISPOSITION_CONTAINERS = ["ha-train-run", "minicpm-train", "uv_build"]
DISPOSITION_ARTIFACTS = ["f5-tts-checkpoint"]
TOP_KEYS = {
    "schema", "inventory_sha256", "expected_retained_databases", "proofs", "retired", "dispositions",
}
FAMILY_KEYS = {
    "family", "containers", "paths", "volumes", "databases", "secrets",
    "images", "family_evidence",
}


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def _exact_keys(value, keys, label):
    if not isinstance(value, dict) or set(value) != keys:
        raise RetirementHalt(f"invalid fields: {label}")


def _sha(value, label):
    if not isinstance(value, str) or not SHA256.fullmatch(value):
        raise RetirementHalt(f"invalid {label} SHA-256")


def _reference(reference, label, schema):
    _exact_keys(reference, {"sha256", "envelope"}, f"{label} reference")
    _sha(reference["sha256"], label)
    if reference["sha256"] != digest(reference["envelope"]):
        raise RetirementHalt(f"evidence hash mismatch: {label}")
    envelope_value = reference["envelope"]
    if not isinstance(envelope_value, dict):
        raise RetirementHalt(f"invalid evidence envelope: {label}")
    if envelope_value.get("schema") != schema or envelope_value.get("status") != "verified":
        raise RetirementHalt(f"unverified evidence: {label}")
    return envelope_value


def _database_reference(reference, inventory_sha256, expected_databases):
    _exact_keys(reference, {"sha256", "envelope"}, "retained database restore reference")
    _sha(reference["sha256"], "retained database restore")
    envelope_value = reference["envelope"]
    if reference["sha256"] != digest(envelope_value):
        raise RetirementHalt("evidence hash mismatch: retained database restore")
    if envelope_value.get("schema") != "kepler-collision-database-evidence-manifest-v1":
        raise RetirementHalt("invalid database planner envelope schema")
    manifest = envelope_value.get("manifest")
    if not isinstance(manifest, dict) or envelope_value.get("manifest_sha256") != digest(manifest):
        raise RetirementHalt("database planner manifest hash mismatch")
    if manifest.get("status") != "retained-databases-verified" or manifest.get("inventory_sha256") != inventory_sha256:
        raise RetirementHalt("database planner inventory/status mismatch")
    retained = manifest.get("retained_databases")
    if not isinstance(retained, list) or [item.get("name") for item in retained] != expected_databases:
        raise RetirementHalt("exact retained database set mismatch")
    artifact_hashes = []
    for item in retained:
        artifact_hash = item.get("artifact", {}).get("sha256")
        if not isinstance(artifact_hash, str) or not SHA256.fullmatch(artifact_hash):
            raise RetirementHalt("retained database artifact hash missing")
        if item.get("restore", {}).get("artifact_sha256") != artifact_hash:
            raise RetirementHalt("retained database restore artifact mismatch")
        artifact_hashes.append(artifact_hash)
    if len(artifact_hashes) != len(set(artifact_hashes)) or manifest.get("retired_databases") != ["airflow"]:
        raise RetirementHalt("invalid retained database artifact coverage")
    return manifest


def _live_containers(inventory):
    records = inventory.get("inventory", {}).get("containers")
    if not isinstance(records, list):
        raise RetirementHalt("fresh inventory containers required")
    result = {}
    for record in records:
        name = record.get("name")
        if not isinstance(name, str) or name in result:
            raise RetirementHalt("unique inventory container names required")
        result[name] = record
    return result


def _check_live(record, live, mount_evidence=False):
    _exact_keys(
        record,
        {"name", "id", "state", "mount_retention"}
        if mount_evidence else {"name", "id", "state"},
        "container evidence",
    )
    name = record["name"]
    actual = live.get(name)
    if actual is None or actual.get("id") != record["id"]:
        raise RetirementHalt(f"inventory ID mismatch: {name}")
    if not CONTAINER_ID.fullmatch(record["id"]):
        raise RetirementHalt(f"invalid container ID: {name}")
    if record["state"] != "exited" or actual.get("state") != "exited":
        raise RetirementHalt(f"container must be exited: {name}")
    if mount_evidence:
        proof = _reference(
            record["mount_retention"], f"mount retention for {name}",
            "kepler-mount-retention-evidence-v1",
        )
        sources = sorted(mount.get("source") for mount in actual.get("mounts", []))
        if proof.get("container_id") != record["id"] or sorted(proof.get("sources", [])) != sources:
            raise RetirementHalt(f"mount retention evidence mismatch: {name}")


def _action(kind, resource, command, rollback):
    return {
        "mode": "dry-run",
        "kind": kind,
        "resource": resource,
        "command": command,
        "abort": "before-command",
        "rollback": rollback,
    }


def plan(inventory, evidence):
    _exact_keys(evidence, TOP_KEYS, "evidence")
    if evidence.get("schema") != "kepler-retirement-evidence-v1":
        raise RetirementHalt("unsupported evidence schema")
    if inventory.get("schema") != "kepler-collision-inventory-v1":
        raise RetirementHalt("unsupported inventory schema")
    computed_inventory_sha256 = digest(inventory.get("inventory"))
    if inventory.get("inventory_sha256") != computed_inventory_sha256:
        raise RetirementHalt("inventory internal SHA-256 mismatch")
    if evidence["inventory_sha256"] != computed_inventory_sha256:
        raise RetirementHalt("evidence is not bound to inventory SHA-256")
    _exact_keys(evidence["proofs"], {"retained_database_restore", "retired_preflight"}, "proofs")
    expected_databases = evidence["expected_retained_databases"]
    if not isinstance(expected_databases, list) or not expected_databases or expected_databases != sorted(set(expected_databases)):
        raise RetirementHalt("exact retained database set required")
    _database_reference(evidence["proofs"]["retained_database_restore"], computed_inventory_sha256, expected_databases)
    preflight = _reference(
        evidence["proofs"]["retired_preflight"], "retired preflight",
        "kepler-retired-preflight-evidence-v1",
    )
    declared_secrets = sorted({secret for policy in RETIRED_ALLOWLIST.values() for secret in policy["secrets"]})
    if preflight.get("declared_secrets") != declared_secrets or preflight.get("secret_artifacts") != declared_secrets:
        raise RetirementHalt("exact retired secret artifact coverage required")
    credentials = preflight.get("external_credentials")
    if not isinstance(credentials, list) or not credentials or preflight.get("external_revocations") != credentials:
        raise RetirementHalt("exact external revocation coverage required")
    historical = preflight.get("declared_historical_artifacts")
    if not isinstance(historical, list) or not historical or preflight.get("historical_artifacts") != historical:
        raise RetirementHalt("exact historical artifact coverage required")
    mixed = preflight.get("declared_mixed_backups")
    if not isinstance(mixed, list) or not mixed or preflight.get("mixed_backup_sanitizations") != mixed or preflight.get("restore_compares") != mixed:
        raise RetirementHalt("mixed-backup sanitation and restore/compare evidence required")
    live = _live_containers(inventory)
    inventory_volumes = inventory["inventory"].get("volumes", [])
    inventory_images = inventory["inventory"].get("images", [])
    live_volumes = {item.get("name"): item for item in inventory_volumes}
    live_images = {"sha256:" + item.get("id", ""): item for item in inventory_images}
    if len(live_volumes) != len(inventory_volumes):
        raise RetirementHalt("duplicate inventory volume identity")
    if len(live_images) != len(inventory_images):
        raise RetirementHalt("duplicate inventory image identity")
    image_references = inventory["inventory"].get("references", {}).get("images", {})

    actions = []
    retired_resources = []
    selected_volume_identities = set()
    selected_runtime_volumes = set()
    selected_image_identities = set()
    families = evidence.get("retired")
    if not isinstance(families, list) or {x.get("family") for x in families} != set(RETIRED_ALLOWLIST):
        raise RetirementHalt("retired families must match exact allowlist")
    for family in sorted(families, key=lambda item: item["family"]):
        _exact_keys(family, FAMILY_KEYS, f"retired.{family.get('family')}")
        name = family["family"]
        policy = RETIRED_ALLOWLIST[name]
        names = [item.get("name") for item in family["containers"]]
        if names != policy["containers"]:
            raise RetirementHalt(f"{name} containers outside exact allowlist")
        for record in family["containers"]:
            _check_live(record, live)
            actions.append(_action(
                "container", record["name"],
                ["just", "kepler-recovery-retire-exact", "container", record["id"]],
                "not-applicable-after-exact-delete",
            ))
        for field in ("paths", "databases", "secrets"):
            if family[field] != policy[field]:
                raise RetirementHalt(f"{name} {field} outside exact allowlist")
        logical_volumes = [item.get("logical_name") for item in family["volumes"]]
        if logical_volumes != policy["volumes"]:
            raise RetirementHalt(f"{name} volumes outside exact allowlist")
        for volume in family["volumes"]:
            _exact_keys(volume, {"logical_name", "runtime_name"}, f"{name} runtime volume")
            actual_volume = live_volumes.get(volume["runtime_name"])
            expected_labels = {
                "com.docker.compose.project": name,
                "com.docker.compose.volume": volume["logical_name"],
            }
            if actual_volume is None or actual_volume.get("labels") != expected_labels:
                raise RetirementHalt(f"runtime volume label mismatch: {volume['logical_name']}")
            identity = (volume["logical_name"], volume["runtime_name"])
            if identity in selected_volume_identities or volume["runtime_name"] in selected_runtime_volumes:
                raise RetirementHalt("duplicate volume identity")
            selected_volume_identities.add(identity)
            selected_runtime_volumes.add(volume["runtime_name"])
        resources = {key: family[key] for key in ("family", "containers", "paths", "volumes", "databases", "secrets", "images")}
        family_proof = _reference(family["family_evidence"], f"{name} family", "kepler-retired-family-evidence-v1")
        if family_proof.get("family") != name or family_proof.get("resources_sha256") != digest(resources):
            raise RetirementHalt(f"{name} family evidence resource mismatch")
        for image in family["images"]:
            _sha(image, f"{name} image identity")
            if image in selected_image_identities:
                raise RetirementHalt("duplicate image identity")
            selected_image_identities.add(image)
            if image not in live_images:
                raise RetirementHalt(f"image identity absent from inventory: {image}")
            if sorted(image_references.get(image, [])) != sorted(policy["containers"]):
                raise RetirementHalt(f"shared image forbidden: {image}")
        for path in family["paths"]:
            actions.append(_action("path", path, ["just", "kepler-recovery-retire-exact", "path", path], "restore-from-verified-sanitized-copy"))
        for volume in family["volumes"]:
            runtime_name = volume["runtime_name"]
            actions.append(_action("volume", runtime_name, ["just", "kepler-recovery-retire-exact", "volume", runtime_name], "not-applicable-after-exact-delete"))
        for database in family["databases"]:
            actions.append(_action("database", database, ["just", "kepler-recovery-retire-exact", "database", database], "restore-from-verified-sanitized-copy"))
        for secret in family["secrets"]:
            actions.append(_action("secret", secret, ["just", "kepler-recovery-retire-exact", "secret", secret], "not-applicable-after-exact-delete"))
        for image in family["images"]:
            actions.append(_action("image", image, ["just", "kepler-recovery-retire-exact", "image", image], "not-applicable-after-exact-delete"))
        retired_resources.append({key: family[key] for key in ("family", "containers", "paths", "volumes", "databases", "secrets", "images", "family_evidence")})

    dispositions = evidence.get("dispositions")
    _exact_keys(dispositions, {"containers", "artifacts"}, "dispositions")
    container_names = [item.get("name") for item in dispositions["containers"]]
    if sorted(container_names) != DISPOSITION_CONTAINERS:
        raise RetirementHalt("container disposition allowlist mismatch")
    disposition_resources = []
    for record in sorted(dispositions["containers"], key=lambda item: item["name"]):
        _check_live(record, live, mount_evidence=True)
        disposition_resources.append({"kind": "container", **record})
        actions.append(_action("container", record["name"], ["just", "kepler-recovery-retire-exact", "container", record["id"]], "not-applicable-after-exact-delete"))
    artifacts = dispositions["artifacts"]
    if len(artifacts) != 1 or artifacts[0].get("name") not in DISPOSITION_ARTIFACTS:
        raise RetirementHalt("artifact disposition allowlist mismatch")
    artifact = artifacts[0]
    _exact_keys(artifact, {"name", "path", "sha256", "path_identity"}, "artifact disposition")
    if posixpath.normpath(artifact["path"]) != artifact["path"] or ".." in artifact["path"].split("/"):
        raise RetirementHalt("f5-tts-checkpoint path must be normalized")
    if not F5_PATH.fullmatch(artifact["path"]):
        raise RetirementHalt("f5-tts-checkpoint exact discovered path required")
    _sha(artifact["sha256"], "f5-tts-checkpoint content")
    path_proof = _reference(
        artifact["path_identity"], "f5-tts-checkpoint path identity",
        "kepler-path-identity-evidence-v1",
    )
    if (
        path_proof.get("type") != "file"
        or path_proof.get("path") != artifact["path"]
        or path_proof.get("content_sha256") != artifact["sha256"]
        or not isinstance(path_proof.get("size"), int)
        or path_proof["size"] < 0
    ):
        raise RetirementHalt("f5-tts-checkpoint path identity mismatch")
    disposition_resources.append({"kind": "artifact", **artifact})
    actions.append(_action("artifact", artifact["path"], ["just", "kepler-recovery-retire-exact", "artifact", artifact["path"]], "not-applicable-after-exact-delete"))

    manifest = {
        "schema": "kepler-retirement-approval-manifest-v1",
        "status": "ready-for-explicit-hash-bound-approval",
        "inventory_sha256": inventory["inventory_sha256"],
        "inventory_envelope_sha256": digest(inventory),
        "evidence_sha256": digest(evidence),
        "retired_allowlist": RETIRED_ALLOWLIST,
        "retired_resources": retired_resources,
        "disposition_resources": sorted(disposition_resources, key=lambda item: item["name"]),
        "actions": actions,
        "execution": "unsupported-by-this-planner",
    }
    return manifest


def envelope(manifest):
    return {"manifest": manifest, "manifest_sha256": digest(manifest)}


def verify(inventory, evidence, wrapper):
    manifest = wrapper.get("manifest")
    if not isinstance(manifest, dict) or wrapper.get("manifest_sha256") != digest(manifest):
        raise RetirementDrift("manifest SHA-256 drift")
    if manifest.get("inventory_envelope_sha256") != digest(inventory):
        raise RetirementDrift("inventory drift")
    if manifest.get("evidence_sha256") != digest(evidence):
        raise RetirementDrift("evidence drift")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inventory")
    parser.add_argument("evidence")
    args = parser.parse_args(argv)
    try:
        with open(args.inventory, encoding="utf-8") as handle:
            inventory = json.load(handle)
        with open(args.evidence, encoding="utf-8") as handle:
            evidence = json.load(handle)
        print(json.dumps(envelope(plan(inventory, evidence)), sort_keys=True))
    except (OSError, json.JSONDecodeError, RetirementHalt) as error:
        print(f"retirement planner halted: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
