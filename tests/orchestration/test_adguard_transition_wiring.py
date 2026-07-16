import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/hosts/discovery/stateful-stack-ops.nix"


class AdguardTransitionWiringTest(unittest.TestCase):
    def setUp(self):
        self.source = MODULE.read_text()

    def test_all_independent_store_sources_are_explicit(self):
        for name in (
            "INVENTORY",
            "PREFLIGHT",
            "FIXTURE",
            "EXECUTOR",
            "REVISION",
            "EXACT_REVISION",
            "POSTCHECK",
        ):
            self.assertIn(f"P2_ADGUARD_{name}_SOURCE=", self.source)
        self.assertIn("P2_ADGUARD_DECLARATIVE_WIRING_SHA256=", self.source)
        self.assertIn("P2_ADGUARD_POSTCHECK_WIRING_SHA256=", self.source)
        self.assertIn("P2_ADGUARD_EXACT_REVISION_BIN=${servarrExactRevision}/bin/servarr-exact-revision", self.source)
        self.assertIn("P2_ADGUARD_POSTCHECK_BIN=${statefulAdguardPostcheck}/bin/discovery-stateful-adguard-postcheck", self.source)
        self.assertIn('builtins.hashFile "sha256" ../../server/_servarr-exact-revision.py', self.source)
        self.assertIn('builtins.hashFile "sha256" ./_stateful-adguard-postcheck.py', self.source)

    def test_execute_dispatches_only_to_executor(self):
        body = self.source.split('name = "discovery-stateful-adguard-transition";', 1)[1]
        body = body.split("    };", 1)[0]
        self.assertIn('execute) exec python3 ${./_stateful-adguard-transition-exec.py} "$@"', body)
        self.assertIn('*) exec python3 ${./_stateful-adguard-transition.py} "$@"', body)

    def test_postcheck_is_a_nix_store_installed_runtime_dependency(self):
        self.assertIn('name = "discovery-stateful-adguard-postcheck";', self.source)
        self.assertIn("${./_stateful-adguard-postcheck.py}", self.source)
        transition = self.source.split('name = "discovery-stateful-adguard-transition";', 1)[1]
        transition = transition.split("    };", 1)[0]
        self.assertIn("statefulAdguardPostcheck", transition)
        packages = self.source.split("environment.systemPackages = [", 1)[1].split("];", 1)[0]
        self.assertIn("statefulAdguardPostcheck", packages)

    def test_p2_evidence_directory_is_group_traversable_for_revision_helper(self):
        self.assertIn(
            '"d /var/lib/stateful-stack-migrations/p2-adguard 0770 root users - -"',
            self.source,
        )


if __name__ == "__main__":
    unittest.main()
