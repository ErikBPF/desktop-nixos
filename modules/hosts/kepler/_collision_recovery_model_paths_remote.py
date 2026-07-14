#!/usr/bin/env python3
"""Discover reviewed Kepler model identity paths without reading contents."""

import argparse
import json
import os
import pathlib
import re
import stat
import sys


LIVE_ROOT = pathlib.Path("/fast/ai-models")
ARTIFACTS = {
    "embeddings-bge-m3": ("embeddings/hub/models--BAAI--bge-m3", "directory"),
    "embeddings-bge-reranker-v2-m3": (
        "embeddings/hub/models--BAAI--bge-reranker-v2-m3", "directory",
    ),
    "f5-tts-reference-audio": ("refs", "directory"),
    "piper-voices": ("piper", "directory"),
}
WHISPER_PATTERNS = (
    "whisper/models--Systran--faster-whisper-large-v3-turbo",
    "whisper/models--mobiuslabsgmbh--faster-whisper-large-v3-turbo",
    "whisper/large-v3-turbo",
)
F5_PARENT = "f5-tts/hf/models--firstpixel--F5-TTS-pt-br/snapshots"
SNAPSHOT = re.compile(r"[0-9a-f]{6,64}")


class DiscoveryHalt(Exception):
    def __init__(self, message, artifact="model-inventory", reason="unsafe-path"):
        super().__init__(message)
        self.artifact = artifact
        self.reason = reason


def _inside(path, root):
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def _validate_entry(path, root, root_device):
    try:
        metadata = path.lstat()
        mode = metadata.st_mode
        if metadata.st_dev != root_device:
            raise DiscoveryHalt("artifact path validation failed")
        if stat.S_ISLNK(mode):
            resolved = path.resolve(strict=True)
            if (
                not _inside(resolved, root)
                or resolved.stat().st_dev != root_device
                or not (resolved.is_file() or resolved.is_dir())
            ):
                raise DiscoveryHalt("artifact path validation failed")
        elif not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
            raise DiscoveryHalt("artifact path validation failed")
    except (OSError, RuntimeError):
        raise DiscoveryHalt("artifact path validation failed") from None


def _validate(path, root, kind):
    root_device = root.stat().st_dev
    _validate_entry(path, root, root_device)
    resolved = path.resolve(strict=True)
    if not _inside(resolved, root) or resolved.stat().st_dev != root_device:
        raise DiscoveryHalt("artifact path validation failed")
    if kind == "file" and not resolved.is_file():
        raise DiscoveryHalt("artifact path validation failed")
    if kind == "directory" and not resolved.is_dir():
        raise DiscoveryHalt("artifact path validation failed")
    if resolved.is_dir():
        for current, directories, files in os.walk(resolved, followlinks=False):
            current_path = pathlib.Path(current)
            for name in directories + files:
                _validate_entry(current_path / name, root, root_device)


def _virtual(path, root):
    return (LIVE_ROOT / path.relative_to(root)).as_posix()


def discover(root=LIVE_ROOT):
    root = pathlib.Path(root).resolve(strict=True)
    if not root.is_dir():
        raise DiscoveryHalt("required artifact path unavailable")
    selected = dict(ARTIFACTS)

    whisper = [relative for relative in WHISPER_PATTERNS if (root / relative).exists()]
    if len(whisper) > 1:
        raise DiscoveryHalt(
            "whisper-model identity path is ambiguous", "whisper-model", "ambiguous",
        )
    if not whisper:
        raise DiscoveryHalt("required artifact path unavailable", "whisper-model", "missing")
    selected["whisper-model"] = (whisper[0], "directory")

    parent = root / F5_PARENT
    f5 = []
    if parent.is_dir():
        for snapshot in parent.iterdir():
            if SNAPSHOT.fullmatch(snapshot.name):
                candidate = snapshot / "pt-br/model_last.safetensors"
                if candidate.exists() or candidate.is_symlink():
                    f5.append(candidate)
    if len(f5) > 1:
        raise DiscoveryHalt(
            "f5-tts-checkpoint identity path is ambiguous",
            "f5-tts-checkpoint", "ambiguous",
        )
    if not f5:
        raise DiscoveryHalt(
            "required artifact path unavailable", "f5-tts-checkpoint", "missing",
        )

    artifacts = []
    for artifact, (relative, kind) in selected.items():
        path = root / relative
        if not path.exists() and not path.is_symlink():
            raise DiscoveryHalt("required artifact path unavailable", artifact, "missing")
        try:
            _validate(path, root, kind)
        except DiscoveryHalt as error:
            raise DiscoveryHalt(str(error), artifact, "unsafe-path") from None
        artifacts.append({
            "artifact": artifact,
            "identity_path": _virtual(path, root),
            "kind": kind,
            "status": "validated",
        })
    try:
        _validate(f5[0], root, "file")
    except DiscoveryHalt as error:
        raise DiscoveryHalt(str(error), "f5-tts-checkpoint", "unsafe-path") from None
    artifacts.append({
        "artifact": "f5-tts-checkpoint",
        "identity_path": _virtual(f5[0], root),
        "kind": "file",
        "status": "validated",
    })
    return {
        "artifacts": sorted(artifacts, key=lambda item: item["artifact"]),
        "schema": "kepler-k1-model-paths-v1",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture-root")
    args = parser.parse_args(argv)
    try:
        result = discover(args.fixture_root or LIVE_ROOT)
        print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    except (DiscoveryHalt, OSError) as error:
        if isinstance(error, DiscoveryHalt):
            artifact, reason = error.artifact, error.reason
        else:
            artifact, reason = "model-inventory", "unsafe-path"
        report = {
            "diagnostics": [{"artifact": artifact, "reason": reason}],
            "schema": "kepler-k1-model-path-diagnostics-v1",
            "status": "halt",
        }
        print(json.dumps(report, sort_keys=True, separators=(",", ":")), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
