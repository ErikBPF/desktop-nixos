import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/server/orchestration.nix"
JUSTFILE = ROOT / "justfile"
DISCOVERY_MODULE = ROOT / "modules/hosts/discovery/stateful-stack-ops.nix"


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

    def test_prefetch_recipe_keeps_git_render_and_helper_unprivileged(self):
        source = JUSTFILE.read_text()
        recipe = source.split("discovery-adguard-revision-prefetch output:", 1)[1]
        recipe = recipe.split("\n# ", 1)[0]
        self.assertIn('helper=$(readlink -f "$(command -v servarr-exact-revision)")', recipe)
        self.assertIn('/nix/store/*/bin/servarr-exact-revision)', recipe)
        self.assertIn('"$helper" prefetch --output "$pending"', recipe)
        self.assertNotIn("sudo -n servarr-exact-revision", recipe)
        self.assertNotIn('sudo -n "$helper"', recipe)
        self.assertNotIn("sudo -n git", recipe)
        self.assertNotIn("sudo -n docker-compose", recipe)

    def test_prefetch_recipe_promotes_only_completed_private_temp(self):
        source = JUSTFILE.read_text()
        recipe = source.split("discovery-adguard-revision-prefetch output:", 1)[1]
        recipe = recipe.split("\n# ", 1)[0]
        self.assertIn("pending=$cache/revision-prefetch.json.pending", recipe)
        self.assertIn('test ! -e "$pending"', recipe)
        self.assertIn('sudo -n test ! -e "$remote"', recipe)
        self.assertIn("trap '\\''rm -f \"$pending\"'\\'' EXIT", recipe)
        self.assertIn("sudo -n /run/current-system/sw/bin/discovery-stateful-adguard-prefetch-publish", recipe)
        self.assertNotIn("sudo -n bash", recipe)
        self.assertNotIn("sudo -n python", recipe)
        self.assertNotIn("sudo -n env", recipe)
        self.assertIn('"sudo -n cat /var/lib/stateful-stack-migrations/p2-adguard/revision-prefetch.json" >"$tmp"', recipe)
        self.assertIn('chmod 0400 "$tmp"', recipe)

    def test_root_publisher_is_declaratively_installed(self):
        source = DISCOVERY_MODULE.read_text()
        self.assertIn('statefulAdguardPrefetchPublish = pkgs.writeShellScriptBin "discovery-stateful-adguard-prefetch-publish"', source)
        self.assertIn("${./_stateful-adguard-prefetch-publish.py}", source)
        packages = source.split("environment.systemPackages = [", 1)[1].split("];", 1)[0]
        self.assertIn("statefulAdguardPrefetchPublish", packages)

    def test_hard_link_publish_is_no_clobber_and_cleanup_preserves_existing_final(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            staging = root / ".revision-prefetch.json.publish"
            final = root / "revision-prefetch.json"
            staging.write_bytes(b"candidate")
            final.write_bytes(b"retained")
            with self.assertRaises(FileExistsError):
                final.hardlink_to(staging)
            staging.unlink(missing_ok=True)
            self.assertEqual(final.read_bytes(), b"retained")
            self.assertFalse(staging.exists())

    def test_copy_failure_cleanup_leaves_no_publishable_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            staging = root / ".revision-prefetch.json.publish"
            final = root / "revision-prefetch.json"
            staging.write_bytes(b"partial")
            staging.unlink(missing_ok=True)
            self.assertFalse(staging.exists())
            self.assertFalse(final.exists())

    def test_post_link_failure_retains_complete_validated_final(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            staging = root / ".revision-prefetch.json.publish"
            final = root / "revision-prefetch.json"
            payload = b'{"contract":{},"contract_sha256":"a","evidence":{},"evidence_sha256":"b"}'
            staging.write_bytes(payload)
            final.hardlink_to(staging)
            # Model EXIT cleanup after a directory-fsync failure.
            staging.unlink(missing_ok=True)
            self.assertFalse(staging.exists())
            self.assertEqual(final.read_bytes(), payload)


if __name__ == "__main__":
    unittest.main()
