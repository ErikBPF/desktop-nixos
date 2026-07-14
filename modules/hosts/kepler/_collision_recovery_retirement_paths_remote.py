#!/usr/bin/env python3
"""Collect value-free metadata for the fixed Kepler retirement path allowlist."""

import hashlib
import json
import pathlib
import stat
import sys


ALLOWLIST = (
    "/bulk/git",
    "/fast/apps/gitlab/config",
    "/fast/apps/gitlab/logs",
    "/fast/apps/gitlab-runner",
    "/fast/apps/airflow/dags",
    "/fast/apps/airflow/plugins",
    "/fast/ai-models/f5-tts",
)


class PathEvidenceHalt(Exception):
    """A fixed retirement path cannot be inspected safely."""


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def _candidate(root, allowed_path):
    candidate = root.joinpath(*pathlib.PurePosixPath(allowed_path).parts[1:])
    relative = candidate.relative_to(root)
    current = root
    for component in relative.parts:
        current /= component
        try:
            metadata = current.lstat()
        except FileNotFoundError:
            break
        except OSError as error:
            raise PathEvidenceHalt(f"metadata unavailable: {allowed_path}") from error
        if stat.S_ISLNK(metadata.st_mode):
            raise PathEvidenceHalt(f"symlink forbidden: {allowed_path}")

    try:
        resolved = candidate.resolve(strict=False)
        resolved.relative_to(root)
    except (OSError, ValueError) as error:
        raise PathEvidenceHalt(f"realpath escape forbidden: {allowed_path}") from error
    return candidate


def _record(root, allowed_path):
    candidate = _candidate(root, allowed_path)
    try:
        metadata = candidate.stat(follow_symlinks=False)
    except FileNotFoundError:
        return {
            "byte_count": None,
            "device": None,
            "existence": False,
            "inode": None,
            "path": allowed_path,
            "type": None,
        }
    except OSError as error:
        raise PathEvidenceHalt(f"metadata unavailable: {allowed_path}") from error

    if stat.S_ISDIR(metadata.st_mode):
        kind = "directory"
    elif stat.S_ISREG(metadata.st_mode):
        kind = "file"
    else:
        raise PathEvidenceHalt(f"unsupported path type: {allowed_path}")
    return {
        "byte_count": metadata.st_size,
        "device": metadata.st_dev,
        "existence": True,
        "inode": metadata.st_ino,
        "path": allowed_path,
        "type": kind,
    }


def collect(root=pathlib.Path("/")):
    if not isinstance(root, pathlib.Path) or not root.is_absolute():
        raise PathEvidenceHalt("absolute evidence root required")
    try:
        root = root.resolve(strict=True)
    except OSError as error:
        raise PathEvidenceHalt("evidence root unavailable") from error
    evidence = [_record(root, path) for path in ALLOWLIST]
    return {
        "evidence": evidence,
        "evidence_sha256": hashlib.sha256(canonical(evidence)).hexdigest(),
        "schema": "kepler-retirement-path-evidence-envelope-v1",
        "status": "verified",
    }


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv:
        print("retirement path evidence halted: remote helper accepts no arguments", file=sys.stderr)
        return 2
    try:
        result = collect()
    except PathEvidenceHalt as error:
        print(f"retirement path evidence halted: {error}", file=sys.stderr)
        return 2
    json.dump(result, sys.stdout, sort_keys=True, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
