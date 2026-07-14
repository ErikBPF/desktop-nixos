#!/usr/bin/env python3
"""Render a deterministic, value-free Kepler K1 quiesce manifest."""

import argparse
import hashlib
import json
import re
import sys


class QuiesceHalt(Exception):
    """The supplied inventory cannot safely produce a quiesce manifest."""


HEX64 = re.compile(r"[0-9a-f]{64}")
COMPOSE_PROJECT = "com.docker.compose.project"
COMPOSE_SERVICE = "com.docker.compose.service"
ACTIVE_STATES = {"paused", "restarting", "running"}
STOP_ORDER = ("docs-search", "ai-serving", "infra")
START_ORDER = tuple(reversed(STOP_ORDER))
RETIRED = {
    "gitlab": {"gitlab", "gitlab-runner"},
    "airflow": {
        "airflow-init",
        "airflow-scheduler",
        "airflow-triggerer",
        "airflow-webserver",
        "airflow-worker",
    },
    "restate": {"restate"},
}


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def _payload(envelope, kind):
    schema = f"kepler-collision-{kind}-v1"
    if not isinstance(envelope, dict) or envelope.get("schema") != schema:
        raise QuiesceHalt(f"invalid {kind} envelope schema")
    payload = envelope.get(kind)
    claimed = str(envelope.get(f"{kind}_sha256", ""))
    if not isinstance(payload, dict) or not HEX64.fullmatch(claimed):
        raise QuiesceHalt(f"invalid {kind} envelope binding")
    if digest(payload) != claimed:
        raise QuiesceHalt(f"{kind} envelope SHA-256 mismatch")
    return payload


def _is_exact_retired(name, labels):
    project = labels.get(COMPOSE_PROJECT, "")
    return (
        project in RETIRED
        and name in RETIRED[project]
        and labels.get(COMPOSE_SERVICE, "") == name
    )


def plan(inventory_envelope, desired_envelope, expected_inventory_sha256):
    inventory = _payload(inventory_envelope, "inventory")
    desired = _payload(desired_envelope, "desired")
    inventory_sha256 = inventory_envelope["inventory_sha256"]
    if not HEX64.fullmatch(str(expected_inventory_sha256)):
        raise QuiesceHalt("invalid expected inventory SHA-256")
    if expected_inventory_sha256 != inventory_sha256:
        raise QuiesceHalt("inventory drift: approval binding does not match")

    services = desired.get("services", [])
    if not isinstance(services, list):
        raise QuiesceHalt("invalid desired services")
    desired_by_name = {}
    for item in services:
        if not isinstance(item, dict) or not all(
            isinstance(item.get(field), str) and item[field]
            for field in ("container_name", "project", "service")
        ):
            raise QuiesceHalt("invalid desired service declaration")
        name = item["container_name"]
        if name in desired_by_name:
            raise QuiesceHalt("duplicate desired container")
        if item["project"] not in STOP_ORDER:
            raise QuiesceHalt("unsupported desired Compose project")
        desired_by_name[name] = item

    if desired.get("protected_services"):
        raise QuiesceHalt("retired service must not remain protected")
    if set(desired_by_name) & set().union(*RETIRED.values()):
        raise QuiesceHalt("retired service must not be active")

    running_by_stack = {stack: [] for stack in STOP_ORDER}
    seen = set()
    containers = inventory.get("containers", [])
    if not isinstance(containers, list):
        raise QuiesceHalt("invalid inventory containers")
    for container in containers:
        if not isinstance(container, dict):
            raise QuiesceHalt("invalid inventory container")
        name = container.get("name", "")
        labels = container.get("labels", {})
        state = container.get("state", "")
        if not isinstance(name, str) or not name or name in seen:
            raise QuiesceHalt("invalid or duplicate inventory container name")
        if not isinstance(labels, dict):
            raise QuiesceHalt("invalid Compose labels")
        seen.add(name)

        desired_item = desired_by_name.get(name)
        if desired_item is None:
            if _is_exact_retired(name, labels):
                if state in ACTIVE_STATES:
                    raise QuiesceHalt("retired container is running")
                continue
            raise QuiesceHalt("unknown, foreign, or unlabeled container")

        if (
            labels.get(COMPOSE_PROJECT) != desired_item["project"]
            or labels.get(COMPOSE_SERVICE) != desired_item["service"]
        ):
            raise QuiesceHalt("declared container has foreign, missing, or mismatched labels")
        if state in ACTIVE_STATES:
            running_by_stack[desired_item["project"]].append(name)

    stacks = [
        {"containers": sorted(running_by_stack[stack]), "stack": stack}
        for stack in STOP_ORDER
        if running_by_stack[stack]
    ]
    actions = [
        {
            "command": (
                f"just kepler-recovery-quiesce-stack {item['stack']} "
                f"{inventory_sha256}"
            ),
            "containers": item["containers"],
            "kind": "stop-compose-stack",
            "stack": item["stack"],
        }
        for item in stacks
    ]
    selected_stacks = {item["stack"] for item in stacks}
    rollback = [
        f"just kick-stack kepler {stack}"
        for stack in START_ORDER
        if stack in selected_stacks
    ]
    manifest = {
        "abort_boundary": "before-first-stop-on-any-drift-or-failed-precondition",
        "actions": actions,
        "downtime": "until-fresh-inventory-and-approved-K1-continuation",
        "execution_supported": False,
        "inventory_sha256": inventory_sha256,
        "mode": "dry-run-only",
        "postcondition": "collect-fresh-read-only-inventory-before-any-K1-continuation",
        "rollback": rollback,
        "stacks": stacks,
        "status": "ready-for-separate-hash-bound-approval" if actions else "nothing-to-quiesce",
        "stop_order": list(STOP_ORDER),
    }
    return {
        "inventory_sha256": inventory_sha256,
        "manifest": manifest,
        "manifest_sha256": digest(manifest),
        "schema": "kepler-collision-quiesce-manifest-v1",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--desired", required=True)
    parser.add_argument("--expected-inventory-sha256", required=True)
    args = parser.parse_args(argv)
    try:
        with open(args.inventory, encoding="utf-8") as handle:
            inventory = json.load(handle)
        with open(args.desired, encoding="utf-8") as handle:
            desired = json.load(handle)
        result = plan(inventory, desired, args.expected_inventory_sha256)
    except (OSError, json.JSONDecodeError, QuiesceHalt) as error:
        print(f"quiesce manifest halted: {error}", file=sys.stderr)
        return 2
    json.dump(result, sys.stdout, sort_keys=True, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
