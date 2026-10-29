#!/usr/bin/env python3
"""Resolve an explicit Graphify update; builds consume the resulting wheel lock."""

import argparse
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
PYTHON_VERSION = "3.14"
PLATFORMS = ("manylinux_2_28_x86_64", "manylinux2014_x86_64", "linux_x86_64")


def lock_from_report(report, version):
    if report.get("version") != "1":
        raise ValueError("Unsupported pip report schema")
    wheels = []
    names = set()
    for item in report["install"]:
        metadata = item["metadata"]
        name = re.sub(r"[-_.]+", "-", metadata["name"]).lower()
        download = item["download_info"]
        url = urlsplit(download["url"])
        filename = url.path.rsplit("/", 1)[-1]
        digest = download.get("archive_info", {}).get("hashes", {}).get("sha256", "")
        if (url.scheme != "https" or url.netloc != "files.pythonhosted.org"
                or url.query or url.fragment or not re.fullmatch(r"[A-Za-z0-9_.+-]+\.whl", filename)
                or not re.fullmatch(r"[a-f0-9]{64}", digest)
                or item.get("is_yanked") or name in names):
            raise ValueError("Expected a unique, non-yanked public wheel with SHA256")
        names.add(name)
        if name == "graphifyy" and metadata["version"] != version:
            raise ValueError("Resolved Graphify version differs from the requested version")
        wheels.append({"filename": filename, "url": download["url"], "sha256": digest})
    if "graphifyy" not in names:
        raise ValueError("Graphify is missing from the resolved closure")
    return {"version": version, "pythonVersion": PYTHON_VERSION, "system": "x86_64-linux",
            "wheels": sorted(wheels, key=lambda wheel: wheel["filename"])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="Explicit graphifyy version to resolve")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9][A-Za-z0-9.+-]*", args.version):
        parser.error("Expected an explicit package version")
    if sys.version_info[:2] != (3, 14) or sys.platform != "linux" or platform.machine() != "x86_64":
        parser.error("Run the updater in the declared Python 3.14 x86_64 Linux development shell")
    with tempfile.TemporaryDirectory(prefix="graphify-lock-") as temporary:
        report_path = Path(temporary) / "report.json"
        environment = {"PATH": os.environ["PATH"], "HOME": temporary,
                       "PIP_CONFIG_FILE": os.devnull, "PIP_DISABLE_PIP_VERSION_CHECK": "1"}
        if "SSL_CERT_FILE" in os.environ:
            environment["SSL_CERT_FILE"] = os.environ["SSL_CERT_FILE"]
        command = [sys.executable, "-m", "pip", "install", "--dry-run", "--ignore-installed",
                   "--no-cache-dir", "--only-binary=:all:", "--index-url", "https://pypi.org/simple",
                   "--python-version", PYTHON_VERSION, "--implementation", "cp"]
        for target_platform in PLATFORMS:
            command.extend(["--platform", target_platform])
        for abi in ("cp314", "abi3", "none"):
            command.extend(["--abi", abi])
        command.extend(["--report", str(report_path), f"graphifyy[mcp]=={args.version}"])
        subprocess.run(command, env=environment, check=True, timeout=300)
        lock = lock_from_report(json.loads(report_path.read_text()), args.version)
    (ROOT / "modules/dev/graphify-lock.json").write_text(json.dumps(lock, indent=2) + "\n")
    print(f"Locked {len(lock['wheels'])} wheels; review the dependency diff before building.")


if __name__ == "__main__":
    main()
