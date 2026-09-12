"""Run the real recipe in disposable repositories; never update fleet inputs."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
JUST = shutil.which("just")


class UpdateSafe(unittest.TestCase):
    def test_transaction(self):
        for mode in ("staged", "unstaged", "update-fail", "build-fail",
                     "update-INT", "update-TERM", "build-INT", "build-TERM",
                     "evidence-fail", "evidence-TERM", "published-TERM", "success"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                repo = Path(directory)
                (repo / "justfile").write_bytes((ROOT / "justfile").read_bytes())
                (repo / "fleet.json").write_bytes((ROOT / "fleet.json").read_bytes())
                (repo / "scripts").mkdir()
                shutil.copy2(ROOT / "scripts" / "upgrade-candidate-evidence.py", repo / "scripts")
                (repo / "bin").mkdir()
                (repo / "tmp").mkdir()
                env = dict(os.environ, PATH=f"{repo / 'bin'}:{os.environ['PATH']}",
                           TMPDIR=str(repo / "tmp"), MODE=mode)

                def git(*args):
                    return subprocess.check_output(["git", *args], cwd=repo, env=env)

                git("init", "-q")
                # Git-clean bytes differ from the working tree: HEAD restore is wrong.
                git("config", "filter.lock.clean", "sed s/worktree/canonical/g")
                git("config", "filter.lock.smudge", "cat")
                (repo / ".gitattributes").write_text("flake.lock filter=lock\n")
                original = b'worktree lock bytes https://user:synthetic-secret@example.invalid\r\n\n'
                lock = repo / "flake.lock"
                lock.write_bytes(original)
                git("add", "flake.lock", ".gitattributes")
                git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                    "commit", "-qm", "baseline")
                baseline = git("rev-parse", "HEAD").decode().strip()
                evidence = repo / ".git" / "upgrade-candidate.json"
                previous = b'{"previous": "receipt"}\n'
                if mode == "evidence-fail":
                    evidence.mkdir()
                else:
                    evidence.write_bytes(previous)
                if mode in ("staged", "unstaged"):
                    original += b"local edit\n"
                    lock.write_bytes(original)
                    if mode == "staged":
                        git("add", "flake.lock")
                index = git("show", ":flake.lock")
                for command, phase in (("nix", "update"), ("just", "build")):
                    stub = repo / "bin" / command
                    stub.write_text(f'''#!/usr/bin/env bash
set -eu
printf '%s\\n' {phase} >> calls
printf '%s\\n' candidate > flake.lock
case "$MODE" in
  {phase}-fail) exit 17;;
  {phase}-INT) kill -INT "$PPID"; exit 0;;
  {phase}-TERM) kill -TERM "$PPID"; exit 0;;
esac
''')
                    stub.chmod(0o755)
                if mode in ("evidence-TERM", "published-TERM"):
                    writer = repo / "bin" / "python3"
                    writer.write_text(f'''#!{sys.executable}
import json
import os
from pathlib import Path
import runpy
import signal
import sys

if os.environ["MODE"] == "evidence-TERM":
    dump = json.dump
    def interrupted_dump(*args, **kwargs):
        dump(*args, **kwargs)
        os.kill(os.getpid(), signal.SIGTERM)
    json.dump = interrupted_dump
else:
    replace = Path.replace
    def interrupted_replace(*args, **kwargs):
        result = replace(*args, **kwargs)
        os.kill(os.getppid(), signal.SIGTERM)
        return result
    Path.replace = interrupted_replace
sys.argv = sys.argv[1:]
runpy.run_path(sys.argv[0], run_name="__main__")
''')
                    writer.chmod(0o755)
                result = subprocess.run([JUST, "update-safe"], cwd=repo, env=env,
                                        capture_output=True, timeout=20)
                self.assertEqual(result.returncode == 0, mode == "success",
                                 result.stderr.decode())
                self.assertEqual(lock.read_bytes(), b"candidate\n" if mode == "success" else original)
                self.assertEqual(git("show", ":flake.lock"), index)
                self.assertEqual(list((repo / "tmp").iterdir()), [])
                calls = (repo / "calls").read_text() if (repo / "calls").exists() else ""
                expected = "" if mode in ("staged", "unstaged") else "update\n"
                if mode.startswith(("build", "evidence", "published")) or mode == "success":
                    expected += "build\n"
                self.assertEqual(calls, expected)
                if mode == "success":
                    receipt = json.loads(evidence.read_bytes())
                    self.assertIn("checked_at", receipt, "successful candidate must replace the previous receipt")
                    timestamp = datetime.fromisoformat(receipt.pop("checked_at"))
                    self.assertEqual(timestamp.utcoffset(), timezone.utc.utcoffset(None))
                    self.assertLess(abs((datetime.now(timezone.utc) - timestamp).total_seconds()), 30)
                    self.assertEqual(receipt, {
                        "baseline_revision": baseline,
                        "before_lock_sha256": hashlib.sha256(original).hexdigest(),
                        "candidate_lock_sha256": hashlib.sha256(b"candidate\n").hexdigest(),
                        "validation": "dry-all",
                    })
                    self.assertNotIn(b"synthetic-secret", evidence.read_bytes())
                elif mode == "evidence-fail":
                    self.assertTrue(evidence.is_dir())
                else:
                    self.assertEqual(evidence.read_bytes(), previous)
                self.assertEqual(list((repo / ".git").glob("upgrade-candidate-*.tmp")), [])
