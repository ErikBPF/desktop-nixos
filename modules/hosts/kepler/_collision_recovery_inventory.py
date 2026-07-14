#!/usr/bin/env python3
"""Collect deterministic, value-free Kepler recovery inventory metadata."""

import argparse
import hashlib
import json
import re
import subprocess
import sys


class InventoryHalt(Exception):
    pass


LIVE_COMMANDS = (
    ("podman", "ps", "--all", "--quiet", "--no-trunc"),
    ("zfs", "list", "-H", "-o", "name,mountpoint"),
)
CONTAINER_ID = re.compile(r"[0-9a-f]{64}")
SOURCE_FIELDS = {"containers", "datasets", "images", "volumes", "networks", "snapshots"}
CONTAINER_FIELDS = {
    "Id", "ID", "Name", "Names", "State", "Status", "Image", "ImageName",
    "ImageDigest", "Labels", "Mounts", "Networks",
}
MOUNT_FIELDS = {"Source", "Destination", "Name"}
COMPOSE_LABELS = {
    "com.docker.compose.project",
    "com.docker.compose.service",
    "com.docker.compose.project.working_dir",
    "com.docker.compose.project.config_files",
}


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def _exact_fields(value, allowed, path):
    if not isinstance(value, dict):
        raise InventoryHalt(f"object required: {path}")
    unknown = set(value) - allowed
    if unknown:
        raise InventoryHalt(f"unknown field forbidden: {path}.{sorted(unknown)[0]}")


def _normalize_mount(mount, path):
    _exact_fields(mount, MOUNT_FIELDS, path)
    return {
        "destination": str(mount.get("Destination", "")),
        "name": str(mount.get("Name", "")),
        "source": str(mount.get("Source", "")),
    }


def _normalize_container(container, index):
    path = f"containers[{index}]"
    _exact_fields(container, CONTAINER_FIELDS, path)
    labels = container.get("Labels") or {}
    if not isinstance(labels, dict):
        raise InventoryHalt(f"object required: {path}.Labels")
    approved_labels = {
        key: str(value) for key, value in labels.items() if key in COMPOSE_LABELS
    }
    mounts = container.get("Mounts") or []
    if not isinstance(mounts, list):
        raise InventoryHalt(f"array required: {path}.Mounts")
    networks = container.get("Networks") or []
    if isinstance(networks, dict):
        networks = list(networks)
    if not isinstance(networks, list):
        raise InventoryHalt(f"array required: {path}.Networks")
    names = container.get("Names", "")
    if isinstance(names, list):
        names = names[0] if names else ""
    return {
        "id": str(container.get("Id", container.get("ID", ""))),
        "image": str(container.get("ImageName", container.get("Image", ""))),
        "image_digest": str(container.get("ImageDigest", "")),
        "image_provenance": "immutable-digest" if container.get("ImageDigest") else "unresolved",
        "labels": dict(sorted(approved_labels.items())),
        "mounts": sorted(
            (_normalize_mount(mount, f"{path}.Mounts[{mount_index}]") for mount_index, mount in enumerate(mounts)),
            key=lambda item: (item["source"], item["destination"], item["name"]),
        ),
        "name": str(container.get("Name", names)).lstrip("/"),
        "networks": sorted(str(network) for network in networks),
        "state": str(container.get("State", container.get("Status", ""))).lower(),
    }


def collect_fixture(source):
    _exact_fields(source, SOURCE_FIELDS, "source")
    containers = source.get("containers", [])
    datasets = source.get("datasets", [])
    if not isinstance(containers, list) or not isinstance(datasets, list):
        raise InventoryHalt("containers and datasets must be arrays")
    normalized_datasets = []
    for index, dataset in enumerate(datasets):
        _exact_fields(dataset, {"name", "mountpoint"}, f"datasets[{index}]")
        normalized_datasets.append({
            "mountpoint": str(dataset.get("mountpoint", "")),
            "name": str(dataset.get("name", "")),
        })
    normalized = {}
    object_schemas = {
        "images": {"id", "digests", "names"},
        "volumes": {"name", "driver", "mountpoint", "labels"},
        "networks": {"id", "name", "driver", "labels"},
        "snapshots": {"name"},
    }
    for kind, fields in object_schemas.items():
        records = source.get(kind, [])
        if not isinstance(records, list):
            raise InventoryHalt(f"{kind} must be an array")
        normalized[kind] = []
        for index, record in enumerate(records):
            _exact_fields(record, fields, f"{kind}[{index}]")
            if kind == "images":
                if not isinstance(record.get("digests"), list) or not isinstance(record.get("names"), list):
                    raise InventoryHalt("image digests and names must be arrays")
                item = {"id": str(record.get("id", "")), "digests": sorted(map(str, record["digests"])), "names": sorted(map(str, record["names"]))}
            elif kind == "snapshots":
                item = {"name": str(record.get("name", ""))}
            else:
                labels = record.get("labels") or {}
                if not isinstance(labels, dict):
                    raise InventoryHalt(f"{kind} labels must be an object")
                item = {key: str(record.get(key, "")) for key in fields - {"labels"}}
                item["labels"] = dict(sorted((key, str(value)) for key, value in labels.items() if key in COMPOSE_LABELS))
            if not all(value for key, value in item.items() if key not in {"labels", "digests", "names", "mountpoint"}):
                raise InventoryHalt(f"{kind}[{index}] omitted required identity metadata")
            normalized[kind].append(item)
    inventory = {
        "containers": sorted(
            (_normalize_container(container, index) for index, container in enumerate(containers)),
            key=lambda item: (item["name"], item["id"]),
        ),
        "datasets": sorted(normalized_datasets, key=lambda item: (item["name"], item["mountpoint"])),
        **{kind: sorted(records, key=lambda item: json.dumps(item, sort_keys=True)) for kind, records in normalized.items()},
    }
    references = {"images": {}, "volumes": {}, "networks": {}}
    for container in inventory["containers"]:
        for image_identity in filter(None, (container["image"], container["image_digest"])):
            references["images"].setdefault(image_identity, []).append(container["name"])
        for mount in container["mounts"]:
            if mount["name"]:
                references["volumes"].setdefault(mount["name"], []).append(container["name"])
        for network in container["networks"]:
            references["networks"].setdefault(network, []).append(container["name"])
    inventory["references"] = {
        kind: {identity: sorted(set(users)) for identity, users in sorted(mapping.items())}
        for kind, mapping in references.items()
    }
    return {
        "inventory": inventory,
        "inventory_sha256": hashlib.sha256(canonical(inventory)).hexdigest(),
        "schema": "kepler-collision-inventory-v1",
    }


def _containers_from_inspect(inspected, requested_ids):
    if not isinstance(inspected, list):
        raise InventoryHalt("podman inspect response must be an array")
    if len(inspected) != len(requested_ids):
        raise InventoryHalt("podman inspect response count mismatch")
    containers = []
    seen_ids = set()
    seen_names = set()
    for index, item in enumerate(inspected):
        if not isinstance(item, dict):
            raise InventoryHalt(f"podman inspect item {index} must be an object")
        config = item.get("Config")
        state = item.get("State")
        network_settings = item.get("NetworkSettings")
        mounts = item.get("Mounts")
        if not all(isinstance(section, dict) for section in (config, state, network_settings)):
            raise InventoryHalt(f"podman inspect item {index} has malformed sections")
        if not isinstance(mounts, list) or not isinstance(config.get("Labels") or {}, dict):
            raise InventoryHalt(f"podman inspect item {index} has malformed mounts or labels")
        container_id = item.get("Id")
        name = item.get("Name")
        image = config.get("Image")
        status = state.get("Status")
        if container_id not in requested_ids or not CONTAINER_ID.fullmatch(str(container_id)):
            raise InventoryHalt("podman inspect returned an unrequested container ID")
        normalized_name = str(name or "").lstrip("/")
        if not normalized_name or not image or not status:
            raise InventoryHalt("podman inspect omitted required name, image, or state")
        if container_id in seen_ids or normalized_name in seen_names:
            raise InventoryHalt("podman inspect returned a duplicate ID or runtime name")
        seen_ids.add(container_id)
        seen_names.add(normalized_name)
        networks = network_settings.get("Networks") or {}
        if not isinstance(networks, dict):
            raise InventoryHalt(f"podman inspect item {index} has malformed networks")
        containers.append({
            "Id": container_id,
            "Image": item.get("Image", ""),
            "ImageName": image,
            "ImageDigest": item.get("ImageDigest", ""),
            "Labels": config.get("Labels") or {},
            "Mounts": mounts,
            "Name": normalized_name,
            "Networks": list(networks),
            "State": status,
        })
    if seen_ids != set(requested_ids):
        raise InventoryHalt("podman inspect response did not match requested IDs")
    return containers


def _run(command):
    completed = subprocess.run(command, check=True, capture_output=True, text=True)
    return completed.stdout


def collect_live():
    try:
        container_ids = _run(LIVE_COMMANDS[0]).splitlines()
        if any(not CONTAINER_ID.fullmatch(container_id) for container_id in container_ids):
            raise InventoryHalt("podman returned an invalid container ID")
        inspected = json.loads(_run(("podman", "container", "inspect", *container_ids))) if container_ids else []
        containers = _containers_from_inspect(inspected, container_ids)
        datasets = []
        for line in _run(LIVE_COMMANDS[1]).splitlines():
            name, mountpoint = line.split("\t", 1)
            datasets.append({"name": name, "mountpoint": mountpoint})
        return collect_fixture({"containers": containers, "datasets": datasets})
    except (json.JSONDecodeError, subprocess.CalledProcessError, ValueError) as error:
        raise InventoryHalt(f"read-only inventory collection failed: {error}") from error


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--fixture")
    source.add_argument("--remote-input", action="store_true")
    source.add_argument("--live", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.fixture:
            with open(args.fixture, encoding="utf-8") as handle:
                result = collect_fixture(json.load(handle))
        elif args.remote_input:
            result = collect_fixture(json.load(sys.stdin))
        else:
            result = collect_live()
        print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    except (OSError, json.JSONDecodeError, InventoryHalt) as error:
        print(f"inventory halted: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
