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
F5_PATH = re.compile(r"/fast/ai-models/f5-tts$")
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
    "restate": {
        "containers": ["restate"],
        "paths": [],
        "volumes": ["restate_data"],
        "databases": [],
        "secrets": [],
    },
}
VOLUME_PROJECT = {"gitlab": "gitlab", "airflow": "airflow", "restate": "orchestration"}
IMAGE_REPOSITORIES = {
    "gitlab": {"docker.io/gitlab/gitlab-ce", "docker.io/gitlab/gitlab-runner"},
    "airflow": {"docker.io/apache/airflow"},
    "restate": {"docker.restate.dev/restatedev/restate"},
}
DISPOSITION_CONTAINERS = ["f5-tts-server", "ha-train-run", "minicpm-train", "uv_build"]
DISPOSITION_ARTIFACTS = ["f5-tts-model-data"]
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
    if (
        not isinstance(retained, list)
        or any(not isinstance(item, dict) or set(item) != {"name", "owner"} for item in retained)
        or [item["name"] for item in retained] != expected_databases
        or len({(item["name"], item["owner"]) for item in retained}) != len(retained)
    ):
        raise RetirementHalt("exact retained database set mismatch")
    artifact = manifest.get("cluster_artifact")
    restore = manifest.get("cluster_restore")
    if (
        not isinstance(artifact, dict)
        or not SHA256.fullmatch(str(artifact.get("sha256", "")))
        or not isinstance(restore, dict)
        or restore.get("artifact_sha256") != artifact["sha256"]
        or restore.get("status") != "passed"
        or restore.get("retained_databases") != expected_databases
        or not SHA256.fullmatch(str(restore.get("database_inventory_sha256", "")))
        or not SHA256.fullmatch(str(restore.get("logical_sha256", "")))
        or manifest.get("retired_databases") != ["airflow"]
    ):
        raise RetirementHalt("invalid retained cluster restore evidence")
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
    allowed_states = {"running"} if name == "f5-tts-server" else {"exited"}
    if record["state"] not in allowed_states or actual.get("state") not in allowed_states:
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
    _exact_keys(evidence["proofs"], {"retained_database_restore", "retired_preflight", "retirement_paths"}, "proofs")
    expected_databases = evidence["expected_retained_databases"]
    if not isinstance(expected_databases, list) or not expected_databases or expected_databases != sorted(set(expected_databases)):
        raise RetirementHalt("exact retained database set required")
    _database_reference(evidence["proofs"]["retained_database_restore"], computed_inventory_sha256, expected_databases)
    preflight = _reference(
        evidence["proofs"]["retired_preflight"], "retired preflight",
        "kepler-retired-preflight-evidence-v1",
    )
    allowed_secrets = {secret for policy in RETIRED_ALLOWLIST.values() for secret in policy["secrets"]}
    declared_secrets = preflight.get("declared_secrets")
    if not isinstance(declared_secrets, list) or len(declared_secrets) != len(set(declared_secrets)) or not set(declared_secrets) <= allowed_secrets or preflight.get("secret_artifacts") != declared_secrets:
        raise RetirementHalt("exact retired secret artifact coverage required")
    credentials = preflight.get("external_credentials")
    if not isinstance(credentials, list) or len(credentials) != len(set(credentials)) or not set(credentials) <= set(declared_secrets) or preflight.get("external_revocations") != credentials:
        raise RetirementHalt("exact external revocation coverage required")
    path_envelope = _reference(evidence["proofs"]["retirement_paths"], "retirement paths", "kepler-retirement-path-evidence-envelope-v1")
    path_records = path_envelope.get("paths")
    if not isinstance(path_records, list) or any(not isinstance(item, dict) or set(item) != {"path", "existence", "type", "device", "inode", "byte_count"} for item in path_records):
        raise RetirementHalt("invalid retirement path evidence")
    path_by_name = {item["path"]: item for item in path_records}
    if len(path_by_name) != len(path_records):
        raise RetirementHalt("duplicate retirement path evidence")
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
        if len(names) != len(set(names)) or not set(names) <= set(policy["containers"]):
            raise RetirementHalt(f"{name} containers outside exact allowlist")
        for record in family["containers"]:
            _check_live(record, live)
            actions.append(_action(
                "container", record["name"],
                ["just", "kepler-recovery-retire-exact", "container", record["id"]],
                "not-applicable-after-exact-delete",
            ))
        for field in ("paths", "databases", "secrets"):
            if len(family[field]) != len(set(family[field])) or not set(family[field]) <= set(policy[field]):
                raise RetirementHalt(f"{name} {field} outside exact allowlist")
        logical_volumes = [item.get("logical_name") for item in family["volumes"]]
        if len(logical_volumes) != len(set(logical_volumes)) or not set(logical_volumes) <= set(policy["volumes"]):
            raise RetirementHalt(f"{name} volumes outside exact allowlist")
        for volume in family["volumes"]:
            _exact_keys(volume, {"logical_name", "runtime_name"}, f"{name} runtime volume")
            actual_volume = live_volumes.get(volume["runtime_name"])
            expected_labels = {
                "com.docker.compose.project": VOLUME_PROJECT[name],
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
        path_identities = family_proof.get("path_identities", [])
        if sorted(item.get("path") for item in path_identities) != sorted(family["paths"]):
            raise RetirementHalt(f"{name} path identity coverage mismatch")
        for item in path_identities:
            record = path_by_name.get(item.get("path"))
            if item.get("envelope_sha256") != evidence["proofs"]["retirement_paths"]["sha256"] or not record or record.get("existence") is not True or record.get("type") != "directory":
                raise RetirementHalt(f"{name} path identity evidence invalid")
        for image in family["images"]:
            _sha(image, f"{name} image identity")
            if image in selected_image_identities:
                raise RetirementHalt("duplicate image identity")
            selected_image_identities.add(image)
            if image not in live_images:
                raise RetirementHalt(f"image identity absent from inventory: {image}")
            image_record = live_images[image]
            repositories = {value.split("@", 1)[0] for value in image_record.get("digests", [])}
            if not repositories or not repositories <= IMAGE_REPOSITORIES[name]:
                raise RetirementHalt(f"retired image repository mismatch: {image}")
            users = image_references.get(image, [])
            if len(users) != len(set(users)) or not set(users) <= set(names):
                raise RetirementHalt(f"shared image forbidden: {image}")
        for path in family["paths"]:
            actions.append(_action("path", path, ["just", "kepler-recovery-retire-exact", "path", path], "not-applicable-disposable-test"))
        for volume in family["volumes"]:
            runtime_name = volume["runtime_name"]
            actions.append(_action("volume", runtime_name, ["just", "kepler-recovery-retire-exact", "volume", runtime_name], "not-applicable-after-exact-delete"))
        for database in family["databases"]:
            actions.append(_action("database", database, ["just", "kepler-recovery-retire-exact", "database", database], "not-applicable-disposable-test"))
        for secret in family["secrets"]:
            actions.append(_action("secret", secret, ["just", "kepler-recovery-retire-exact", "secret", secret], "not-applicable-after-exact-delete"))
        for image in family["images"]:
            actions.append(_action("image", image, ["just", "kepler-recovery-retire-exact", "image", image], "not-applicable-after-exact-delete"))
        retired_resources.append({key: family[key] for key in ("family", "containers", "paths", "volumes", "databases", "secrets", "images", "family_evidence")})

    dispositions = evidence.get("dispositions")
    _exact_keys(dispositions, {"containers", "artifacts", "images"}, "dispositions")
    container_names = [item.get("name") for item in dispositions["containers"]]
    expected_dispositions = [name for name in DISPOSITION_CONTAINERS if name in live]
    if sorted(container_names) != expected_dispositions:
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
    _exact_keys(artifact, {"name", "path", "path_evidence_sha256"}, "artifact disposition")
    if posixpath.normpath(artifact["path"]) != artifact["path"] or ".." in artifact["path"].split("/"):
        raise RetirementHalt("f5-tts-checkpoint path must be normalized")
    if not F5_PATH.fullmatch(artifact["path"]):
        raise RetirementHalt("f5-tts-checkpoint exact discovered path required")
    path_proof = path_by_name.get(artifact["path"])
    if artifact["path_evidence_sha256"] != evidence["proofs"]["retirement_paths"]["sha256"] or not path_proof or path_proof.get("existence") is not True or path_proof.get("type") != "directory" or not all(isinstance(path_proof.get(field), int) and path_proof[field] >= 0 for field in ("device", "inode", "byte_count")):
        raise RetirementHalt("f5-tts-checkpoint path identity mismatch")
    disposition_resources.append({"kind": "artifact", **artifact})
    actions.append(_action("artifact", artifact["path"], ["just", "kepler-recovery-retire-exact", "artifact", artifact["path"]], "not-applicable-after-exact-delete"))
    images = dispositions["images"]
    if len(images) != 1 or set(images[0]) != {"name", "identity", "container"}:
        raise RetirementHalt("F5 image disposition required")
    f5_image = images[0]
    if f5_image["name"] != "f5-tts-image" or f5_image["container"] != "f5-tts-server":
        raise RetirementHalt("F5 image disposition mismatch")
    if f5_image["identity"] not in live_images:
        raise RetirementHalt("F5 image identity absent from inventory")
    expected_f5_references = ["f5-tts-server"] if "f5-tts-server" in live else []
    if image_references.get(f5_image["identity"], []) != expected_f5_references:
        raise RetirementHalt("F5 image is shared or unbound")
    disposition_resources.append({"kind": "image", **f5_image})
    actions.append(_action("image", f5_image["identity"], ["just", "kepler-recovery-retire-exact", "image", f5_image["identity"]], "not-applicable-after-exact-delete"))

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
