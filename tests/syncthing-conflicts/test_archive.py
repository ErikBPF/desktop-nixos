import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/archive-syncthing-conflicts.py'


class ConflictArchive(unittest.TestCase):
    def test_preview_then_archive_preserves_original_and_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            root = base / 'Documents'
            root.mkdir()
            original = root / 'notes.md'
            original.write_text('current work')
            conflict = root / 'notes.sync-conflict-20260907-190756-T27S3JE.md'
            conflict.write_text('older work')
            before = conflict.stat()
            archive = base / 'archive'
            args = [sys.executable, str(SCRIPT), '--archive', str(archive), str(root)]
            preview = subprocess.run(args, capture_output=True, text=True)
            self.assertEqual(preview.returncode, 0, preview.stderr)
            self.assertTrue(conflict.exists())
            self.assertFalse(archive.exists())
            applied = subprocess.run(args + ['--apply'], capture_output=True, text=True)
            self.assertEqual(applied.returncode, 0, applied.stderr)
            self.assertFalse(conflict.exists())
            self.assertEqual(original.read_text(), 'current work')
            rows = json.loads((archive / 'manifest.json').read_text())
            saved = archive / 'files' / str(conflict).lstrip('/')
            self.assertEqual(len(rows), 1)
            self.assertEqual(saved.read_text(), 'older work')
            self.assertEqual(saved.stat().st_mtime_ns, before.st_mtime_ns)
            self.assertEqual(archive.stat().st_mode & 0o777, 0o700)
            repeat = subprocess.run(args + ['--apply'], capture_output=True, text=True)
            self.assertNotEqual(repeat.returncode, 0)
            self.assertEqual(saved.read_text(), 'older work')

    def test_refuses_archive_inside_sync_root_and_conflict_symlinks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / 'original.txt'
            target.write_text('keep')
            conflict = root / 'file.sync-conflict-20260907-190756-T27S3JE.txt'
            conflict.symlink_to(target)
            for archive in [root / 'archive', root.parent / (root.name + '-archive')]:
                result = subprocess.run([sys.executable, str(SCRIPT), '--archive', str(archive), str(root), '--apply'], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(archive.exists())
                self.assertTrue(conflict.is_symlink())
                self.assertEqual(target.read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()
