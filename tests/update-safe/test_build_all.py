"""Exercise build selection without realizing or copying any fleet closure."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class BuildAll(unittest.TestCase):
    def test_evaluated_host_selection(self):
        for mode in ("all", "only-endeavour", "only-remote", "eval-fail", "empty",
                     "invalid", "remote-fail", "local-fail"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                repo = Path(directory)
                for name in ("justfile", "fleet.json"):
                    shutil.copy2(ROOT / name, repo / name)
                (repo / "bin").mkdir()
                hosts = ["apollo", "archinaut", "endeavour", "future-host", "orion"]
                if mode == "only-endeavour":
                    hosts = ["endeavour"]
                elif mode == "only-remote":
                    hosts.remove("endeavour")
                elif mode == "empty":
                    hosts = []
                elif mode == "invalid":
                    hosts = ["apollo", "--option injected true"]
                env = dict(os.environ, PATH=f"{repo / 'bin'}:{os.environ['PATH']}",
                           BUILD_ALL_MODE=mode, BUILD_ALL_HOSTS=json.dumps(hosts))
                nix = repo / "bin" / "nix"
                nix.write_text(f'''#!{sys.executable}
import json
import os
from pathlib import Path
import sys
args = sys.argv[1:]
with Path("calls.jsonl").open("a") as calls:
    calls.write(json.dumps(args) + "\\n")
mode = os.environ["BUILD_ALL_MODE"]
if args[0] == "eval":
    if mode == "eval-fail":
        sys.exit(23)
    print(os.environ["BUILD_ALL_HOSTS"])
elif args[0] == "build":
    remote = bool(args[args.index("--builders") + 1])
    if (remote and mode == "remote-fail") or (not remote and mode == "local-fail"):
        sys.exit(17)
else:
    sys.exit(99)
''')
                nix.chmod(0o755)
                result = subprocess.run([shutil.which("just"), "build-all"], cwd=repo,
                                        env=env, capture_output=True, timeout=20)
                calls = [json.loads(line) for line in (repo / "calls.jsonl").read_text().splitlines()]
                self.assertEqual(calls[0][0], "eval", "enumerate before building")
                self.assertIn(".#nixosConfigurations", calls[0])
                self.assertIn("builtins.attrNames", calls[0])
                blocked = mode in ("eval-fail", "empty", "invalid", "remote-fail", "local-fail")
                self.assertEqual(result.returncode != 0, blocked, result.stderr.decode())
                if mode in ("eval-fail", "empty", "invalid"):
                    self.assertEqual(len(calls), 1, "failed enumeration must not start a build")
                    continue
                remote_hosts = sorted(set(hosts) - {"endeavour"})
                builds = calls[1:]
                if remote_hosts:
                    remote = builds.pop(0)
                    self.assertEqual(sorted(a for a in remote if a.startswith(".#")),
                                     [f".#nixosConfigurations.{h}.config.system.build.toplevel"
                                      for h in remote_hosts])
                    self.assertTrue(remote[remote.index("--builders") + 1])
                    for flag in ("--no-link", "--builders-use-substitutes", "--max-jobs", "--keep-going"):
                        self.assertIn(flag, remote)
                if "endeavour" in hosts and mode != "remote-fail":
                    local = builds.pop(0)
                    self.assertEqual([a for a in local if a.startswith(".#")],
                                     [".#nixosConfigurations.endeavour.config.system.build.toplevel"])
                    self.assertEqual(local[local.index("--builders") + 1], "")
                self.assertEqual(builds, [])
