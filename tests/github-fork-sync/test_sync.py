"""Exercise the actual manual helper against fake Git; never contact a remote."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ForkSyncTest(unittest.TestCase):
    def test_native_helper_preserves_fast_forward_and_failure_boundaries(self):
        source = (ROOT / 'modules/desktop/github-fork-sync.nix').read_text()
        body = textwrap.dedent(source.split("      text = ''", 1)[1].split("      '';", 1)[0])
        body = body.replace("''${", '${')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / 'repo with spaces'
            (repo / '.git').mkdir(parents=True)
            git = root / 'git'
            git.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALLS"\n[ "$3" != "$FAIL_COMMAND" ]\n')
            git.chmod(0o700)
            body = '\n'.join('for entry in ' + shlex.quote(str(repo)+':upstream:main:fork') + '; do'
                             if line.lstrip().startswith('for entry in ') else line
                             for line in body.splitlines())
            for failure in ('', 'fetch', 'push', 'missing'):
                with self.subTest(failure=failure):
                    calls = root / 'calls'
                    calls.write_text('')
                    if failure == 'missing':
                        (repo / '.git').rmdir()
                    env = dict(os.environ, PATH=str(root)+':'+os.environ['PATH'], CALLS=str(calls), FAIL_COMMAND=failure)
                    result = subprocess.run(['bash', '-c', body], env=env, capture_output=True, text=True, timeout=5)
                    lines = calls.read_text().splitlines()
                    self.assertEqual(result.returncode, 1 if failure in ('fetch','push') else 0)
                    self.assertEqual(len(lines), {'':2,'fetch':1,'push':2,'missing':0}[failure])
                    self.assertTrue(all('--force' not in line for line in lines))
                    if len(lines) == 2:
                        self.assertTrue(lines[1].endswith('push fork refs/remotes/upstream/main:refs/heads/main'))


if __name__ == '__main__':
    unittest.main()
