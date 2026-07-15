#!/usr/bin/env python3
"""Capture a value-free, read-only Discovery SWAG adoption inventory."""

import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys


REPOSITORY = pathlib.Path("/home/erik/servarr")
WORKING_DIR = REPOSITORY / "machines/discovery"
COMPOSE_FILE = WORKING_DIR / "networking.yml"
ENV_FILE = WORKING_DIR / ".env"
VAULT_ENV = pathlib.Path("/run/vault-agent/networking.env")
CERT = WORKING_DIR / "config/swag/etc/letsencrypt/live/homelab.pastelariadev.com/fullchain.pem"
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


def _run(command, *, binary=False):
    return subprocess.check_output(command, stderr=subprocess.DEVNULL, text=not binary)


def normalize(raw):
    containers = []
    for inspect in raw["container_inspects"]:
        labels = inspect["Config"]["Labels"]
        containers.append({
            "compose_project": labels.get("com.docker.compose.project"),
            "compose_service": labels.get("com.docker.compose.service"),
            "compose_working_dir": labels.get("com.docker.compose.project.working_dir"),
            "id": inspect["Id"],
            "image_id": inspect["Image"],
            "image_ref": inspect["Config"]["Image"],
            "mounts": sorted(
                ({"source": mount["Source"], "target": mount["Destination"], "type": mount["Type"]} for mount in inspect["Mounts"]),
                key=lambda mount: (mount["target"], mount["source"]),
            ),
            "name": inspect["Name"].removeprefix("/"),
            "state": inspect["State"]["Status"],
        })
    return {
        "certificate": raw["certificate"],
        "containers": sorted(containers, key=lambda container: container["name"]),
        "evidence": EVIDENCE,
        "evidence_collisions": sorted(raw["evidence_collisions"]),
        "servarr": {
            "commit": raw["servarr_commit"],
            "compose_file": str(COMPOSE_FILE),
            "render_sha256": raw["servarr_render_sha256"],
        },
    }


def capture():
    inspect = json.loads(_run(["docker", "inspect", "swag", "swag-init"]))
    commit = _run(["git", "-C", str(REPOSITORY), "rev-parse", "HEAD"]).strip()
    render = _run([
        "docker-compose", "--project-name", "networking",
        "--env-file", str(ENV_FILE), "--env-file", str(VAULT_ENV),
        "-f", str(COMPOSE_FILE), "config",
    ], binary=True)
    fingerprint = _run(["openssl", "x509", "-in", str(CERT), "-noout", "-fingerprint", "-sha256"]).split("=", 1)[1].strip().replace(":", "").lower()
    san_output = _run(["openssl", "x509", "-in", str(CERT), "-noout", "-ext", "subjectAltName"])
    sans = sorted(set(re.findall(r"DNS:([^,\s]+)", san_output)))
    enddate = _run(["openssl", "x509", "-in", str(CERT), "-noout", "-enddate"]).split("=", 1)[1].strip()
    not_after = _run(["date", "--utc", "--date", enddate, "+%Y-%m-%dT%H:%M:%SZ"]).strip()
    return normalize({
        "certificate": {"fingerprint_sha256": fingerprint, "not_after": not_after, "sans": sans},
        "container_inspects": inspect,
        "evidence_collisions": [path for path in EVIDENCE.values() if os.path.lexists(path)],
        "servarr_commit": commit,
        "servarr_render_sha256": hashlib.sha256(render).hexdigest(),
    })


def capture_runtime():
    inspect = json.loads(_run(["docker", "inspect", "swag", "swag-init"]))
    raw = {
        "certificate": {},
        "container_inspects": inspect,
        "evidence_collisions": [],
        "servarr_commit": "",
        "servarr_render_sha256": "",
    }
    return {"containers": normalize(raw)["containers"]}


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("capture", "capture-runtime", "normalize"))
    parser.add_argument("input", nargs="?")
    args = parser.parse_args(argv)
    try:
        if args.command in {"capture", "capture-runtime"}:
            if args.input is not None:
                parser.error("capture takes no input")
            result = capture() if args.command == "capture" else capture_runtime()
        else:
            if args.input is None:
                parser.error("normalize requires raw observations")
            result = normalize(json.loads(pathlib.Path(args.input).read_text()))
    except (KeyError, OSError, subprocess.CalledProcessError, json.JSONDecodeError, ValueError) as error:
        print(f"stateful-swag-inventory: BLOCKED: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
