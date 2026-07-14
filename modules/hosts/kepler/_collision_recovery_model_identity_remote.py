#!/usr/bin/env python3
"""Hash reviewed Kepler model paths without emitting contents or entry names."""

import argparse
import hashlib
import json
import os
import pathlib
import sys


LIVE_ROOT = pathlib.Path("/fast/ai-models")
ALGORITHM = "kepler-tree-sha256-v1"


class IdentityHalt(Exception):
    def __init__(self, artifact, reason):
        super().__init__(reason)
        self.artifact = artifact
        self.reason = reason


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def inside(path, root):
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def hash_file(path):
    content_digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            content_digest.update(chunk)
            size += len(chunk)
    return size, content_digest.digest()


def tree_identity(path, root, expected_kind, artifact):
    root = root.resolve(strict=True)
    root_device = root.stat().st_dev
    digest = hashlib.sha256()
    byte_count = 0
    entry_count = 0

    def visit(candidate, logical, active):
        nonlocal byte_count, entry_count
        try:
            metadata = candidate.lstat()
            resolved = candidate.resolve(strict=True)
            resolved_metadata = resolved.stat()
        except (OSError, RuntimeError):
            raise IdentityHalt(artifact, "unsafe-path") from None
        if (
            not inside(resolved, root)
            or metadata.st_dev != root_device
            or resolved_metadata.st_dev != root_device
        ):
            raise IdentityHalt(artifact, "unsafe-path")
        inode = (resolved_metadata.st_dev, resolved_metadata.st_ino)
        if inode in active:
            raise IdentityHalt(artifact, "unsafe-path")
        entry_count += 1
        logical_bytes = logical.as_posix().encode()
        digest.update(len(logical_bytes).to_bytes(8, "big"))
        digest.update(logical_bytes)
        if resolved.is_file():
            digest.update(b"F")
            size, content_sha256 = hash_file(resolved)
            digest.update(size.to_bytes(16, "big"))
            digest.update(content_sha256)
            byte_count += size
        elif resolved.is_dir():
            digest.update(b"D")
            try:
                children = sorted(resolved.iterdir(), key=lambda item: os.fsencode(item.name))
            except OSError:
                raise IdentityHalt(artifact, "unsafe-path") from None
            for child in children:
                visit(child, logical / child.name, active | {inode})
        else:
            raise IdentityHalt(artifact, "unsafe-path")

    try:
        resolved_kind = "file" if path.resolve(strict=True).is_file() else "directory"
    except (OSError, RuntimeError):
        raise IdentityHalt(artifact, "unsafe-path") from None
    if resolved_kind != expected_kind:
        raise IdentityHalt(artifact, "kind-mismatch")
    visit(path, pathlib.PurePosixPath("."), set())
    return {
        "algorithm": ALGORITHM,
        "artifact": artifact,
        "byte_count": byte_count,
        "entry_count": entry_count,
        "sha256": digest.hexdigest(),
        "status": "recorded",
    }


def identities(request, root):
    if request.get("schema") != "kepler-k1-model-paths-v1":
        raise IdentityHalt("model-inventory", "invalid-schema")
    artifacts = request.get("artifacts")
    if not isinstance(artifacts, list):
        raise IdentityHalt("model-inventory", "invalid-schema")
    if any(not isinstance(item, dict) for item in artifacts):
        raise IdentityHalt("model-inventory", "invalid-schema")
    names = [item.get("artifact") for item in artifacts]
    duplicates = sorted({name for name in names if names.count(name) > 1 and isinstance(name, str)})
    if duplicates:
        raise IdentityHalt(duplicates[0], "duplicate-artifact")
    results = []
    for item in sorted(artifacts, key=lambda value: value.get("artifact", "")):
        artifact = item.get("artifact")
        kind = item.get("kind")
        raw_path = item.get("identity_path")
        if not isinstance(artifact, str) or kind not in {"file", "directory"} or not isinstance(raw_path, str):
            raise IdentityHalt("model-inventory", "invalid-schema")
        path = pathlib.Path(raw_path)
        if not path.is_absolute():
            raise IdentityHalt(artifact, "unsafe-path")
        results.append(tree_identity(path, root, kind, artifact))
    evidence = {
        "artifacts": results,
        "algorithm": ALGORITHM,
        "schema": "kepler-k1-model-identities-v1",
    }
    return {
        "evidence": evidence,
        "evidence_sha256": hashlib.sha256(canonical(evidence)).hexdigest(),
        "schema": "kepler-k1-model-identities-envelope-v1",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture-root")
    args = parser.parse_args(argv)
    root = pathlib.Path(args.fixture_root) if args.fixture_root else LIVE_ROOT
    try:
        request = json.load(sys.stdin)
        result = identities(request, root)
        print(canonical(result).decode())
    except (IdentityHalt, OSError, ValueError, json.JSONDecodeError) as error:
        if isinstance(error, IdentityHalt):
            artifact, reason = error.artifact, error.reason
        else:
            artifact, reason = "model-inventory", "invalid-input"
        report = {
            "diagnostics": [{"artifact": artifact, "reason": reason}],
            "schema": "kepler-k1-model-identity-diagnostics-v1",
            "status": "halt",
        }
        print(canonical(report).decode(), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
