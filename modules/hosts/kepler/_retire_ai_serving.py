#!/usr/bin/env python3
"""Exactly retire the operator-approved disposable Kepler AI stack."""

import hashlib
import json
import pathlib
import re
import subprocess
import sys

APPROVED = {
    "edge-tts-openai": ("3d8ba3258db42fc479a683b488577bbfd518b32f819c8ac2d708d66597c73a3d", "sha256:49526a563e8b2cf806db6ce04a30c4590265d7df57d462a08dafa3b3b0823a44"),
    "faster-whisper-openai": ("36f60c2e8bac88f9254daaa9a2b42063f7c5df48fa948d4454e22a422c5ed245", "sha256:4647d4c162af26af8b6f8375f3584d95143f013ad336cc91b16a5647deb84e5d"),
    "nvidia-gpu-exporter": ("63a448710a5b464ef1b0bc4ae76b3e5211ba8359fde09bd0932bf96110a4b0b8", "sha256:255bf21dc420b76fc78378b79063ce0a1fe745b2abbc11cd6e7cbd2a0b8aa5a0"),
    "piper-openai": ("c641c017d24c82b7cb2fc8752072e369d3ab3155e33ad0bbe10088f86dd85426", "sha256:9a3b6052ea1da7f9ba89d76ffaedcba493460546514a2b6f298a92544d3b5c97"),
    "piper-wyoming": ("e7cf7ef4db460e930e2ee19e332c4675b8d6daa966c6fe72b9f76f6e50ff5dae", "sha256:9689c2f5cd65ac830e8e21f3ec03404158f5881d2e16ecaf44dc6614dbcc22f8"),
    "slm-bge-m3": ("1ede3332ec1e228f8bf5398232a232c7bd52c39be29e3b0825ee7a5837aecc83", "sha256:9707b27e7b845abd1d5f0e2b47bd31e64697aab8f1df956081a2f42e2c1174bc"),
    "slm-bge-reranker": ("20edb2f377e6a817c605e699303d233b0b97d8049cf4666668ae1f3f7e510bdc", "sha256:f50bc806338120e138d774236098580f7e5840dbe8bc001ef64615847c1685e8"),
}
CONTAINERS = {container for container, _image in APPROVED.values()}
IMAGES = {image for _container, image in APPROVED.values()}
PATH = "/fast/ai-models"
HEX64 = re.compile(r"[0-9a-f]{64}")
IMAGE_ID = re.compile(r"sha256:[0-9a-f]{64}")


def run(*command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout


def canonical_image_id(value):
    if HEX64.fullmatch(value):
        return "sha256:" + value
    if IMAGE_ID.fullmatch(value):
        return value
    raise ValueError("invalid image identity")


def inspect_all():
    ids = run("podman", "ps", "-aq").splitlines()
    return json.loads(run("podman", "container", "inspect", *ids)) if ids else []


def inspect_images():
    present = set()
    for image in sorted(IMAGES):
        result = subprocess.run(["podman", "image", "inspect", image], capture_output=True, text=True)
        if result.returncode == 0:
            inspected = json.loads(result.stdout)
            if (not isinstance(inspected, list) or len(inspected) != 1
                    or canonical_image_id(inspected[0].get("Id", "")) != image):
                raise ValueError("image inspect identity drifted")
            present.add(image)
        elif result.returncode != 125:
            raise subprocess.CalledProcessError(result.returncode, result.args)
    return present


def identity(item):
    labels = item.get("Config", {}).get("Labels") or {}
    mounts = []
    for mount in item.get("Mounts") or []:
        mounts.append({"destination": str(mount.get("Destination", "")),
                       "source": str(mount.get("Source", "")),
                       "type": str(mount.get("Type", ""))})
    return {"id": item.get("Id", ""), "image": canonical_image_id(item.get("Image", "")),
            "mounts": sorted(mounts, key=lambda value: (value["type"], value["source"], value["destination"])),
            "name": item.get("Name", "").lstrip("/"),
            "project": labels.get("com.docker.compose.project", "")}


def canonical_hash(value):
    data = (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()
    return hashlib.sha256(data).hexdigest()


def plan(items, present_images, path_exists):
    records = sorted((identity(item) for item in items), key=lambda item: (item["name"], item["id"]))
    if any(not HEX64.fullmatch(item["id"]) or not IMAGE_ID.fullmatch(item["image"]) for item in records):
        raise ValueError("invalid sanitized runtime identity")
    if not set(present_images).issubset(IMAGES):
        raise ValueError("unexpected image identity")
    survivors = {item["project"] for item in records if item["name"] not in APPROVED}
    if not {"infra", "docs-search"}.issubset(survivors):
        raise ValueError("infra/docs-search survivor contract missing")
    if any(item["name"] not in APPROVED and item["image"] in IMAGES for item in records):
        raise ValueError("selected image is shared")
    model_path = pathlib.PurePosixPath(PATH)
    for item in records:
        if item["name"] in APPROVED:
            continue
        for mount in item["mounts"]:
            if mount["type"] != "bind" or not mount["source"].startswith("/"):
                continue
            source = pathlib.PurePosixPath(mount["source"])
            if source == model_path or source.is_relative_to(model_path) or model_path.is_relative_to(source):
                raise ValueError("survivor bind overlaps model path")

    selected = [item for item in records
                if item["id"] in CONTAINERS or item["name"] in APPROVED or item["project"] == "ai-serving"]
    exact = [{"id": container, "image": image, "name": name, "project": "ai-serving"}
             for name, (container, image) in APPROVED.items()]
    exact.sort(key=lambda item: (item["name"], item["id"]))
    inventory_sha256 = canonical_hash(records)
    if selected:
        selected_core = [{key: item[key] for key in ("id", "image", "name", "project")}
                         for item in selected]
        if selected_core != exact:
            raise ValueError("exact approved container identities drifted")
        if set(present_images) != IMAGES or not path_exists:
            raise ValueError("container stage has partial image/path state")
        stage = "remove-containers"
        images = []
        remove_path = False
    elif present_images:
        stage = "remove-images"
        images = sorted(present_images)
        remove_path = False
    elif path_exists:
        stage = "remove-path"
        images = []
        remove_path = True
    else:
        stage = "already-retired"
        images = []
        remove_path = False
    manifest = {
        "containers": sorted(CONTAINERS) if stage == "remove-containers" else [],
        "images": images, "inventory_sha256": inventory_sha256,
        "path": PATH, "remove_path": remove_path,
        "schema": "kepler-ai-serving-retirement-v2", "stage": stage,
    }
    manifest["manifest_sha256"] = canonical_hash(manifest)
    return manifest


def observe():
    return plan(inspect_all(), inspect_images(), pathlib.Path(PATH).exists())


def main():
    if sys.argv[1:] != ["--execute-user-approved"]:
        raise SystemExit("execution requires --execute-user-approved")
    try:
        while True:
            first = observe()
            second = observe()
            if first != second:
                raise ValueError("full sanitized inventory drifted before execution")
            if second["stage"] == "already-retired":
                print(json.dumps({"manifest_sha256": second["manifest_sha256"], "status": "already-retired"}, sort_keys=True))
                return
            if second["stage"] == "remove-containers":
                subprocess.run(["podman", "rm", "--force", *second["containers"]], check=True)
            elif second["stage"] == "remove-images":
                subprocess.run(["podman", "image", "rm", *second["images"]], check=True)
            elif second["stage"] == "remove-path":
                subprocess.run(["sudo", "rm", "--one-file-system", "--recursive", "--force", "--", PATH], check=True)
    except (json.JSONDecodeError, subprocess.CalledProcessError, ValueError) as error:
        raise SystemExit(f"AI retirement halted: {error}") from error


if __name__ == "__main__":
    main()
