#!/usr/bin/env python3
"""Archive reviewed conflict copies with sync paused; preserve current originals."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat

CONFLICT = re.compile(r'\.sync-conflict-\d{8}-\d{6}-[A-Z0-9]+(?:\.|$)')


def describe(path):
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), 'rb') as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode):
            raise ValueError(f'Not a regular file: {path}')
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        after = os.fstat(stream.fileno())
    fields = ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_mode', 'st_uid', 'st_gid')
    if any(getattr(before, key) != getattr(after, key) for key in fields):
        raise ValueError(f'Changed during read: {path}')
    return dict(path=str(path), sha256=digest, **{key: getattr(after, key) for key in fields})


def scan_error(error):
    raise error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('roots', type=Path, nargs='+')
    args = parser.parse_args()
    roots = [root.resolve(strict=True) for root in args.roots]
    archive = args.archive.resolve()
    if archive.exists() or any(archive.is_relative_to(root) for root in roots):
        parser.error('Archive must be new and outside every sync root')
    paths = set()
    for root in roots:
        if not root.is_dir():
            parser.error('Every root must be a directory')
        for here, dirs, files in os.walk(root, followlinks=False, onerror=scan_error):
            for name in dirs + files:
                if CONFLICT.search(name):
                    path = Path(here) / name
                    if not stat.S_ISREG(path.lstat().st_mode):
                        parser.error(f'Conflict is not a regular file: {path}')
                    paths.add(path)
    rows = [describe(path) for path in sorted(paths)]
    print(json.dumps({'files': len(rows), 'bytes': sum(row['st_size'] for row in rows), 'apply': args.apply}), flush=True)
    if not args.apply:
        return
    archive.mkdir(parents=True, mode=0o700)
    for row in rows:
        source = Path(row['path'])
        target = archive / 'files' / source.relative_to('/')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target, follow_symlinks=False)
        copied = describe(target)
        if any(copied[key] != row[key] for key in ('sha256', 'st_size', 'st_mtime_ns', 'st_mode')):
            raise ValueError(f'Archive verification failed: {source}')
        with target.open('rb') as stream:
            os.fsync(stream.fileno())
    with (archive / 'manifest.json').open('x') as stream:
        json.dump(rows, stream, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    # Recheck every source before removing any; stop on concurrent writes.
    if any(describe(Path(row['path'])) != row for row in rows):
        raise ValueError('Source changed; archive retained, originals untouched')
    for row in rows:
        source = Path(row['path'])
        if describe(source) != row:
            raise ValueError(f'Source changed; stop cleanup: {source}')
        source.unlink()
    print(f'Archived and verified {len(rows)} conflict copies in {archive}')


if __name__ == '__main__':
    main()
