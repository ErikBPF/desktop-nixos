import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/server/orchestration.nix"


class ExactRevisionWiringTest(unittest.TestCase):
    def setUp(self):
        self.source = MODULE.read_text()

    def test_exact_commit_precedes_branch_and_never_fetches(self):
        exact = self.source.split('if [ -e "$REPO/.deploy-commit" ]; then', 1)[1]
        exact, branch = exact.split(
            "else\n                        EXACT_PIN_ACTIVE=0\n                        BRANCH=",
            1,
        )
        self.assertIn(".pin.version == 1", exact)
        self.assertIn('show -s --format=%T "$PINNED_COMMIT"', exact)
        self.assertIn('cat-file -e "$PINNED_COMMIT^{commit}"', exact)
        self.assertIn('reset --hard "$PINNED_COMMIT"', exact)
        self.assertNotIn(" fetch ", exact)
        self.assertIn('fetch --prune origin "$BRANCH"', branch)

    def test_malformed_or_missing_exact_object_fails_closed(self):
        for message in (
            "malformed exact revision pin",
            "exact revision pin hash differs",
            "exact revision object absent",
            "exact revision tree differs",
            "exact revision activation differs",
            "exact revision render differs",
        ):
            self.assertIn(message, self.source)
        self.assertNotIn("rm -f \"$REPO/.deploy-commit\"", self.source)

    def test_declarative_helper_is_installed(self):
        self.assertIn('name = "servarr-exact-revision";', self.source)
        self.assertIn("${./_servarr-exact-revision.py}", self.source)
        self.assertIn("servarrExactRevision", self.source)


if __name__ == "__main__":
    unittest.main()
