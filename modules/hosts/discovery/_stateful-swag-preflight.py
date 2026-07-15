#!/usr/bin/env python3
"""Value-free, mutation-free SWAG adoption preflight planner."""

import argparse
import hashlib
import json
import pathlib
import re
import sys


class PreflightHalt(ValueError):
    pass


class InventoryDrift(PreflightHalt):
    pass


PROJECT = "networking"
WORKING_DIR = "/home/erik/servarr/machines/discovery"
CONFIG_SOURCE = f"{WORKING_DIR}/config/swag"
IMAGES = {
    "swag": "lscr.io/linuxserver/swag:5.6.0-ls467@sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d",
    "swag-init": "busybox:1.38@sha256:fd8d9aa63ba2f0982b5304e1ee8d3b90a210bc1ffb5314d980eb6962f1a9715d",
}
STATES = {"swag": "running", "swag-init": "exited"}
EVIDENCE = {
    "archive": "/var/lib/stateful-stack-migrations/p1-swag/swag-config.tar.zst",
    "archive_sha256": "/var/lib/stateful-stack-migrations/p1-swag/swag-config.tar.zst.sha256",
    "approved_inventory": "/var/lib/stateful-stack-migrations/p1-swag/approved-inventory.json",
    "authorization": "/var/lib/stateful-stack-migrations/p1-swag/authorization.json",
    "baseline": "/var/lib/stateful-stack-migrations/p1-swag/baseline.json",
    "kindle_png": "/var/lib/stateful-stack-migrations/p1-swag/kindle.png",
    "ledger": "/var/lib/stateful-stack-migrations/p1-swag/ledger.json",
    "result": "/var/lib/stateful-stack-migrations/p1-swag/result.json",
    "restore_target": "/var/lib/stateful-stack-migrations/p1-swag/restore-only-after-approval",
    "rollback_evidence": "/var/lib/stateful-stack-migrations/p1-swag/rollback-evidence.txt",
    "snapshot": "/home/.snapshots/stateful-stack-p1-swag",
}
# Any execute/rollback semantic change must change an ordered action or bump
# this version. The authorization hash deliberately binds this whole object.
WORKFLOW_CONTRACT = {
    "execute_order": [
        "capture-and-verify-fresh-inventory",
        "validate-no-clobber-evidence-set",
        "persist-authorization-and-inventory",
        "create-ledger-and-baseline",
        "reinspect-both-container-identities",
        "stop-captured-swag-id",
        "snapshot-and-archive-stopped-state",
        "recreate-swag-init-then-swag",
        "validate-health-state-certificate-and-routes",
        "persist-result-and-rollback-evidence",
    ],
    "rollback": {
        "implementation": "fixed-compose-swag-recreate-v1",
        "pre_adoption_recovery": "start-exact-stopped-approved-swag-id-v1",
        "required_retained_evidence": ["approved_inventory", "authorization", "archive", "archive_sha256", "ledger", "snapshot"],
    },
    "version": 1,
}
FORBIDDEN_KEYS = {"credential", "env", "environment", "password", "secret", "secret_value", "token", "token_value"}
HEX64 = re.compile(r"^[0-9a-f]{64}$")
HEX40 = re.compile(r"^[0-9a-f]{40}$")
IMAGE_ID = re.compile(r"^sha256:[0-9a-f]{64}$")


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()


def inventory_hash(inventory):
    return hashlib.sha256(canonical(inventory)).hexdigest()


def _reject_value_fields(value):
    if isinstance(value, dict):
        for key, child in value.items():
            lowered = key.lower()
            if lowered in FORBIDDEN_KEYS or lowered.endswith("_secret") or lowered.endswith("_password") or lowered.endswith("_token"):
                raise PreflightHalt(f"value-bearing field forbidden: {key}")
            _reject_value_fields(child)
    elif isinstance(value, list):
        for child in value:
            _reject_value_fields(child)


def _require_keys(value, expected, context):
    if not isinstance(value, dict) or set(value) != set(expected):
        raise PreflightHalt(f"{context} fields differ")


def _validate_container(container, name):
    _require_keys(container, {"compose_project", "compose_service", "compose_working_dir", "id", "image_id", "image_ref", "mounts", "name", "state"}, name)
    if container["name"] != name or container["compose_service"] != name:
        raise PreflightHalt(f"{name} identity differs")
    if container["compose_project"] != PROJECT or container["compose_working_dir"] != WORKING_DIR:
        raise PreflightHalt(f"{name} Compose ownership differs")
    if container["state"] != STATES[name] or not HEX64.fullmatch(container["id"]):
        raise PreflightHalt(f"{name} runtime identity differs")
    if container["image_ref"] != IMAGES[name] or not IMAGE_ID.fullmatch(container["image_id"]):
        raise PreflightHalt(f"{name} immutable image identity differs")
    expected_mount = [{"source": CONFIG_SOURCE, "target": "/config", "type": "bind"}]
    if container["mounts"] != expected_mount:
        raise PreflightHalt(f"{name} /config mount differs")


def plan(inventory):
    _reject_value_fields(inventory)
    _require_keys(inventory, {"certificate", "containers", "evidence", "evidence_collisions", "servarr"}, "inventory")
    if not isinstance(inventory["containers"], list) or len(inventory["containers"]) != 2:
        raise PreflightHalt("container allowlist differs")
    containers = {item.get("name"): item for item in inventory["containers"] if isinstance(item, dict)}
    if set(containers) != set(IMAGES):
        raise PreflightHalt("container allowlist differs")
    for name in ("swag", "swag-init"):
        _validate_container(containers[name], name)

    _require_keys(inventory["servarr"], {"commit", "compose_file", "render_sha256"}, "servarr")
    servarr = inventory["servarr"]
    if not HEX40.fullmatch(servarr["commit"]) or not HEX64.fullmatch(servarr["render_sha256"]):
        raise PreflightHalt("Servarr identity differs")
    if servarr["compose_file"] != f"{WORKING_DIR}/networking.yml":
        raise PreflightHalt("Compose file differs")

    _require_keys(inventory["certificate"], {"fingerprint_sha256", "not_after", "sans"}, "certificate")
    certificate = inventory["certificate"]
    if not HEX64.fullmatch(certificate["fingerprint_sha256"]):
        raise PreflightHalt("certificate fingerprint differs")
    if certificate["sans"] != ["*.homelab.pastelariadev.com"] or not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", certificate["not_after"]):
        raise PreflightHalt("certificate metadata differs")

    if inventory["evidence"] != EVIDENCE or inventory["evidence_collisions"] != []:
        raise PreflightHalt("evidence paths differ or collide")
    if len(set(inventory["evidence"].values())) != len(EVIDENCE):
        raise PreflightHalt("evidence paths collide")

    resources = []
    for name in ("swag", "swag-init"):
        item = containers[name]
        resources.append({
            "compose_project": item["compose_project"],
            "compose_service": item["compose_service"],
            "compose_working_dir": item["compose_working_dir"],
            "id": item["id"],
            "image_id": item["image_id"],
            "image_ref": item["image_ref"],
            "mounts": item["mounts"],
            "name": name,
            "state": item["state"],
        })
    return {
        "certificate": certificate,
        "evidence": inventory["evidence"],
        "inventory_sha256": inventory_hash(inventory),
        "mode": "preflight-only",
        "phase": "p1-swag-in-place-adoption",
        "resources": resources,
        "servarr": servarr,
        "version": 1,
        "workflow_contract": WORKFLOW_CONTRACT,
    }


def envelope(manifest):
    return {"manifest": manifest, "manifest_sha256": hashlib.sha256(canonical(manifest)).hexdigest()}


def verify(inventory, authorization):
    try:
        expected = envelope(plan(inventory))
    except PreflightHalt as error:
        raise InventoryDrift(str(error)) from error
    if authorization != expected:
        raise InventoryDrift("inventory or manifest binding differs")
    return {"inventory_sha256": expected["manifest"]["inventory_sha256"], "manifest_sha256": expected["manifest_sha256"], "status": "binding-valid"}


def _read(path):
    return json.loads(pathlib.Path(path).read_text())


def main(argv=None):
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    create = subparsers.add_parser("plan")
    create.add_argument("inventory")
    check = subparsers.add_parser("verify")
    check.add_argument("inventory")
    check.add_argument("authorization")
    args = parser.parse_args(argv)
    try:
        result = envelope(plan(_read(args.inventory))) if args.command == "plan" else verify(_read(args.inventory), _read(args.authorization))
    except (OSError, json.JSONDecodeError, PreflightHalt) as error:
        print(f"stateful-swag-preflight: BLOCKED: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
