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
                      "invalid", "missing-config", "build-fail"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                repo = Path(directory)
                for name in ("justfile", "fleet.json"):
                    shutil.copy2(ROOT / name, repo / name)
                (repo / "bin").mkdir()
                (repo / "scripts").mkdir()
                selector = ROOT / "scripts" / "upgrade-hosts.nix"
                if selector.exists():
                    shutil.copy2(selector, repo / "scripts")
                hosts = ["apollo", "archinaut", "endeavour", "future-host", "orion"]
                if mode == "only-endeavour":
                    hosts = ["endeavour"]
                elif mode == "only-remote":
                    hosts.remove("endeavour")
                elif mode == "empty":
                    hosts = []
                elif mode == "invalid":
                    hosts = ["apollo", "--option injected true"]
                fleet = " ".join(f'{h}.role = "server";' for h in hosts if not h.startswith("--"))
                configurations = " ".join(f"{h} = {{}};" for h in hosts
                                          if not h.startswith("--") and not (mode == "missing-config" and h == "apollo"))
                (repo / "flake.nix").write_text(
                    "{ outputs = { self }: { fleet.hosts = { " + fleet +
                    ' homeassistant.role = "appliance"; }; nixosConfigurations = { ' +
                    configurations + " drtest = {}; }; }; }"
                )
                env = dict(os.environ, PATH=f"{repo / 'bin'}:{os.environ['PATH']}",
                           BUILD_ALL_MODE=mode, BUILD_ALL_HOSTS=json.dumps(hosts))
                nix = repo / "bin" / "nix"
                nix.write_text(f'''#!{sys.executable}
import json
import os
from pathlib import Path
import subprocess
import sys
args = sys.argv[1:]
with Path("calls.jsonl").open("a") as calls:
    calls.write(json.dumps(args) + "\\n")
mode = os.environ["BUILD_ALL_MODE"]
if args[0] == "eval":
    if mode == "eval-fail":
        sys.exit(23)
    if mode == "invalid":
        print(os.environ["BUILD_ALL_HOSTS"])
    else:
        sys.exit(subprocess.run([{shutil.which("nix")!r}, *args, "--offline",
                                 "--no-write-lock-file", "--option",
                                 "allow-import-from-derivation", "false"]).returncode)
elif args[0] == "build":
    if mode == "build-fail":
        sys.exit(17)
else:
    sys.exit(99)
''')
                nix.chmod(0o755)
                result = subprocess.run([shutil.which("just"), "--no-dotenv", "build-all"], cwd=repo,
                                        env=env, capture_output=True, timeout=20)
                calls = [json.loads(line) for line in (repo / "calls.jsonl").read_text().splitlines()]
                self.assertEqual(calls[0][0], "eval", "enumerate before building")
                blocked = mode in ("eval-fail", "empty", "invalid", "missing-config", "build-fail")
                self.assertEqual(result.returncode != 0, blocked, result.stderr.decode())
                if mode in ("eval-fail", "empty", "invalid", "missing-config"):
                    self.assertTrue(all(c[0] == "eval" for c in calls),
                                    "failed enumeration must not start a build")
                    continue
                evaluations = [c for c in calls if c[0] == "eval"]
                self.assertTrue(any(".#fleet.hosts" in c for c in evaluations))
                self.assertTrue(any(".#nixosConfigurations" in c for c in evaluations))
                builds = [c for c in calls if c[0] == "build"]
                self.assertEqual(len(builds), 1, "one batch; failed compilation is not retried")
                batch = builds[0]
                self.assertEqual(sorted(a for a in batch if a.startswith(".#")),
                                 [f".#nixosConfigurations.{h}.config.system.build.toplevel"
                                  for h in sorted(hosts)])
                builders = batch[batch.index("--builders") + 1]
                self.assertIn("orion-builder:2222", builders)
                self.assertIn("apollo-builder:2222", builders)
                self.assertNotIn("kepler", builders)
                self.assertEqual(batch[batch.index("--max-jobs") + 1], "1")
                for flag in ("--no-link", "--builders-use-substitutes", "--keep-going"):
                    self.assertIn(flag, batch)
