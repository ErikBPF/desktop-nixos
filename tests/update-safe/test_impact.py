"""Evaluate input-free local flakes without realizing any derivation."""

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SECRET = "synthetic-private-reference"


class UpgradeImpact(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def flake(self, name, versions=None, expression=None, managed=None):
        path = self.root / name
        path.mkdir()
        if expression is None:
            expression = "{ " + " ".join(
                f'{host}.config.system.build.toplevel = builtins.derivation {{ '
                f'name = "{host}-{version}"; system = "x86_64-linux"; '
                'builder = "/nonexistent-upgrade-impact-builder"; };'
                for host, version in versions.items()
            ) + " }"
        managed = list(versions if versions is not None else {"apollo": None}) if managed is None else managed
        roles = " ".join(f'{host}.role = "server";' for host in managed)
        (path / "flake.nix").write_text(
            '{ outputs = { self }: { fleet.hosts = { '
            + roles + ' homeassistant.role = "appliance"; }; nixosConfigurations = '
            + expression + '; }; }'
        )
        return str(path)

    def run_impact(self, before, after):
        return subprocess.run(
            [shutil.which("just"), "--justfile", str(ROOT / "justfile"),
             "upgrade-impact", before, after],
            capture_output=True, text=True, timeout=30,
        )

    def test_evaluated_leaf_shared_and_unchanged(self):
        baseline = {"apollo": "v1", "future": "v1", "endeavour": "v1"}
        before = self.flake("before", baseline)
        for label, versions, affected in [
            ("equal", baseline, set()),
            ("leaf", dict(baseline, apollo="v2"), {"apollo"}),
            ("shared", dict.fromkeys(baseline, "v2"), set(baseline)),
        ]:
            with self.subTest(label=label):
                after = self.flake(label, versions)
                result = self.run_impact(before, after)
                self.assertEqual(result.returncode, 0, result.stderr)
                report = json.loads(result.stdout)
                self.assertEqual(set(report), {"affected", "unchanged"})
                self.assertEqual(set(report["affected"]), affected)
                self.assertEqual(set(report["unchanged"]), set(baseline) - affected)
                for host, change in report["affected"].items():
                    self.assertEqual(set(change), {"before", "after"})
                    self.assertNotEqual(change["before"], change["after"])
                    for identity in change.values():
                        self.assertRegex(identity, r"^/nix/store/[0-9a-z]{32}-.*\.drv$")
                for identity in report["unchanged"].values():
                    self.assertRegex(identity, r"^/nix/store/[0-9a-z]{32}-.*\.drv$")
                self.assertFalse((Path(after) / "flake.lock").exists())
        self.assertFalse((Path(before) / "flake.lock").exists())

    def test_topology_changes_and_invalid_identity_fail_closed(self):
        before = self.flake("before", {"apollo": "v1"})
        cases = {
            "added": self.flake("added", {"apollo": "v1", "future": "v1"}),
            "removed": self.flake("removed", {"future": "v1"}),
            "empty": self.flake("empty", {}),
            "invalid": self.flake("invalid", expression=
                '{ apollo.config.system.build.toplevel.drvPath = "' + SECRET + '"; }'),
            "missing-managed": self.flake("missing-managed", {"apollo": "v1"},
                managed=["apollo", "future"]),
        }
        for label, after in cases.items():
            with self.subTest(label=label):
                result = self.run_impact(before, after)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertNotIn(SECRET, result.stderr)

    def test_appliances_and_auxiliary_configurations_are_excluded(self):
        versions = {"apollo": "v1", "homeassistant": "v1", "drtest": "v1"}
        before = self.flake("before", versions, managed=["apollo"])
        after = self.flake("after", dict(versions, homeassistant="v2", drtest="v2"),
            managed=["apollo"])
        result = self.run_impact(before, after)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["affected"], {})
        self.assertEqual(set(report["unchanged"]), {"apollo"})

    def test_evaluation_errors_are_sanitized(self):
        valid = self.flake("valid", {"apollo": "v1"})
        invalid = self.flake(SECRET, expression=f'builtins.throw "{SECRET}"')
        for before, after in [(invalid, valid), (valid, invalid)]:
            with self.subTest(before=before):
                result = self.run_impact(before, after)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertNotIn(SECRET, result.stderr)

    def test_snapshot_arguments_are_literal(self):
        before = self.flake("before $(printf substituted)", {"apollo": "v1"})
        after = self.flake("after ' quoted", {"apollo": "v1"})
        result = self.run_impact(before, after)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["affected"], {})

    def test_attribute_fragments_are_rejected_without_echoing(self):
        valid = self.flake("valid", {"apollo": "v1"})
        result = self.run_impact(valid + "#" + SECRET, valid)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertNotIn(SECRET, result.stderr)
