"""Run the real recipe in disposable repositories; never update fleet inputs."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
JUST = shutil.which("just")


class UpdateSafe(unittest.TestCase):
    def test_transaction(self):
        for mode in ("staged", "unstaged", "update-fail", "build-fail",
                     "update-INT", "update-TERM", "build-INT", "build-TERM", "success"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                repo = Path(directory)
                (repo / "justfile").write_bytes((ROOT / "justfile").read_bytes())
                (repo / "fleet.json").write_bytes((ROOT / "fleet.json").read_bytes())
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
                original = b'worktree lock bytes\r\n\n'
                lock = repo / "flake.lock"
                lock.write_bytes(original)
                git("add", "flake.lock", ".gitattributes")
                git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                    "commit", "-qm", "baseline")
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
                result = subprocess.run([JUST, "update-safe"], cwd=repo, env=env,
                                        capture_output=True, timeout=20)
                self.assertEqual(result.returncode == 0, mode == "success",
                                 result.stderr.decode())
                self.assertEqual(lock.read_bytes(), b"candidate\n" if mode == "success" else original)
                self.assertEqual(git("show", ":flake.lock"), index)
                self.assertEqual(list((repo / "tmp").iterdir()), [])
                calls = (repo / "calls").read_text() if (repo / "calls").exists() else ""
                expected = "" if mode in ("staged", "unstaged") else "update\n"
                if mode.startswith("build") or mode == "success":
                    expected += "build\n"
                self.assertEqual(calls, expected)
