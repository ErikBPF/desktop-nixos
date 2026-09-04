import os
import pathlib
import re
import subprocess
import tempfile
import textwrap
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
        self.assertIn('$machine == "discovery"', exact)
        self.assertIn('show -s --format=%T "$PINNED_COMMIT"', exact)
        self.assertIn('cat-file -e "$PINNED_COMMIT^{commit}"', exact)
        self.assertIn('reset --hard "$PINNED_COMMIT"', exact)
        self.assertNotIn(" fetch ", exact)
        self.assertIn('fetch --prune origin "$BRANCH"', branch)

    def test_generic_v2_pin_is_machine_bound_and_skips_migration_render(self):
        exact = self.source.split('if [ -e "$REPO/.deploy-commit" ]; then', 1)[1]
        exact = exact.split("else\n                        EXACT_PIN_ACTIVE=0", 1)[0]
        self.assertIn(".pin.version == 2", exact)
        self.assertIn('.pin.machine == $machine', exact)
        self.assertIn('PIN_VERSION="$(', exact)
        self.assertIn(
            'if [ "$EXACT_PIN_ACTIVE" -eq 1 ] && [ "$PIN_VERSION" -eq 1 ]; then',
            self.source,
        )

    def test_generic_v2_operator_prefetches_published_commit_then_pins_host(self):
        source = JUSTFILE.read_text()
        recipe = source.split("pin-servarr target commit:", 1)[1]
        recipe = recipe.split("\n# ", 1)[0]
        self.assertIn("target={{ quote(target) }}", recipe)
        self.assertIn("commit={{ quote(commit) }}", recipe)
        self.assertIn('[[ "$commit" =~ ^[0-9a-f]{40}$ ]]', recipe)
        self.assertIn('[[ "$target" =~ ^[a-z0-9-]+$ ]]', recipe)
        self.assertIn(".hosts[$h].tailscaleIp // .hosts[$h].ip", recipe)
        fetch = (
            'git -C "$repo" fetch --prune origin '
            'refs/heads/main:refs/remotes/origin/main'
        )
        pin = '"$helper" pin-v2 "$commit" "$target"'
        self.assertIn(fetch, recipe)
        self.assertIn(
            'flock -x /run/lock/servarr-repository.lock git -C "$repo" fetch',
            recipe,
        )
        self.assertIn(pin, recipe)
        self.assertIn('"$helper" --help 2>&1 | grep -q pin-v2', recipe)
        self.assertLess(recipe.index(fetch), recipe.index(pin))
        self.assertIn('systemctl --user restart servarr-pull.service', recipe)
        self.assertIn(
            'sudo -n /run/current-system/sw/bin/systemctl start', recipe
        )
        self.assertNotIn("sudo systemctl", recipe)
        self.assertNotIn('sudo -n "$helper"', recipe)

    def test_rollout_status_is_value_free_and_fails_closed_on_runtime_health(self):
        source = JUSTFILE.read_text()
        recipe = source.split('servarr-rollout-status target commit="":', 1)[1]
        recipe = recipe.split("\n# ", 1)[0]
        self.assertIn("target={{ quote(target) }}", recipe)
        self.assertIn("commit={{ quote(commit) }}", recipe)
        self.assertIn(".hosts[$h].tailscaleIp // .hosts[$h].ip", recipe)
        self.assertIn('expected="${2-}"', recipe)
        self.assertIn('(keys | sort) == ["pin", "pin_sha256"]', recipe)
        self.assertIn('jq -jcS .pin', recipe)
        self.assertIn('rev-parse HEAD', recipe)
        self.assertIn('show -s --format=%T HEAD', recipe)
        self.assertIn('systemctl --user is-active servarr-pull.service', recipe)
        self.assertIn('/nix/store/*/bin/servarr-exact-revision)', recipe)
        self.assertIn('"$helper" --help 2>&1 | grep -q pin-v2', recipe)
        self.assertIn('kepler) stacks=(infra buzz monitoring sync security retrieval)', recipe)
        self.assertIn('orion) stacks=(shared monitoring ai-models sync)', recipe)
        self.assertIn('voyager) stacks=(offsite)', recipe)
        self.assertIn('systemctl --user is-enabled "$unit"', recipe)
        self.assertIn('systemctl --user is-active "$unit" >/dev/null', recipe)
        self.assertIn('running/healthy/0', recipe)
        self.assertIn('running/none/0', recipe)
        self.assertIn('buzz-minio-init/exited/none/0', recipe)
        self.assertIn('restic-rest-init/exited/none/0', recipe)
        self.assertNotIn('|exited/none/0)', recipe)
        self.assertIn('die() { echo "BLOCKED: $*"', recipe)
        self.assertIn('die "rollout unit inactive', recipe)
        self.assertIn('die "rollout container unhealthy', recipe)
        self.assertIn('die "expected exact pin missing', recipe)
        self.assertIn('runtime_sha256=', recipe)
        self.assertNotIn('inspect="$(docker inspect', recipe)
        self.assertNotIn('docker inspect "$id"', recipe)

    def test_orion_backup_stack_has_a_declarative_rollout_unit(self):
        compose = (ROOT / "modules/hosts/orion/compose.nix").read_text()
        self.assertIn('"sync" # restic backup', compose)

    def test_rollout_status_remote_shell_parses(self):
        recipe = JUSTFILE.read_text().split(
            'servarr-rollout-status target commit="":', 1
        )[1].split("\n# ", 1)[0]
        remote = recipe.split("<<'REMOTE'\n", 1)[1].rsplit("\n    REMOTE", 1)[0]
        result = subprocess.run(
            ["bash", "-n"],
            input=textwrap.dedent(remote),
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_branch_pull_refuses_to_overwrite_policy_while_exact_pin_exists(self):
        source = JUSTFILE.read_text()
        recipe = source.split('pull-servarr target branch="main":', 1)[1]
        recipe = recipe.split("\n# ", 1)[0]
        guard = 'test ! -e "$repo/.deploy-commit"'
        write = '> "$repo/.deploy-branch"'
        self.assertIn(guard, recipe)
        self.assertIn("BLOCKED: exact Servarr revision pin exists", recipe)
        self.assertLess(recipe.index(guard), recipe.index(write))

    def test_branch_pull_validates_ref_and_passes_it_as_remote_argument(self):
        source = JUSTFILE.read_text()
        recipe = source.split('pull-servarr target branch="main":', 1)[1]
        recipe = recipe.split("\n# ", 1)[0]
        self.assertIn("branch={{ quote(branch) }}", recipe)
        self.assertIn('git check-ref-format --branch "$branch"', recipe)
        self.assertIn('bash -s -- "$branch" <<\'REMOTE\'', recipe)
        self.assertIn('branch="$1"', recipe)
        self.assertIn('printf \'%s\\n\' "$branch"', recipe)
        self.assertNotIn("{{branch}}", recipe)

    def test_branch_pull_rejects_remote_shell_metacharacters(self):
        with tempfile.TemporaryDirectory() as directory:
            fake_ssh = pathlib.Path(directory) / "ssh"
            fake_ssh.write_text("#!/bin/sh\nexit 99\n")
            fake_ssh.chmod(0o755)
            env = os.environ.copy()
            env["PATH"] = f"{directory}:{env['PATH']}"
            for branch in ("feature;x", "feature/$(id)", "feature/`id`"):
                with self.subTest(branch=branch):
                    result = subprocess.run(
                        ["just", "pull-servarr", "discovery", branch],
                        cwd=ROOT,
                        env=env,
                        text=True,
                        capture_output=True,
                        check=False,
                    )
                    self.assertEqual(result.returncode, 2)
                    self.assertIn("BLOCKED: invalid branch", result.stderr)

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
        self.assertIn('sudo -n /run/current-system/sw/bin/test ! -e "$remote"', recipe)
        self.assertIn("trap '\\''rm -f \"$pending\"'\\'' EXIT", recipe)
        self.assertIn("sudo -n /run/current-system/sw/bin/discovery-stateful-adguard-prefetch-publish", recipe)
        self.assertNotIn("sudo -n bash", recipe)
        self.assertNotIn("sudo -n python", recipe)
        self.assertNotIn("sudo -n env", recipe)
        self.assertIn('"sudo -n /run/current-system/sw/bin/cat /var/lib/stateful-stack-migrations/p2-adguard/revision-prefetch.json" >"$tmp"', recipe)
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

    def test_all_p2_privileged_commands_use_noninteractive_absolute_entrypoints(self):
        source = JUSTFILE.read_text()
        p2 = source.split("# P2 read-only inventory.", 1)[1]
        p2 = p2.split("# Build Discovery's generated disko script", 1)[0]
        self.assertIsNone(re.search(r"\bsudo\s+(?!-n\s)", p2))
        for command in (
            "/run/current-system/sw/bin/test",
            "/run/current-system/sw/bin/cat",
            "/run/current-system/sw/bin/cmp",
            "/run/current-system/sw/bin/discovery-stateful-adguard-prefetch-publish",
            "/run/current-system/sw/bin/discovery-stateful-adguard-transition plan",
            "/run/current-system/sw/bin/discovery-stateful-adguard-transition verify",
            "/run/current-system/sw/bin/discovery-stateful-adguard-transition execute",
            "/run/current-system/sw/bin/discovery-stateful-adguard-inventory capture",
            "/run/current-system/sw/bin/discovery-stateful-adguard-inventory exporter-families",
        ):
            self.assertIn("sudo -n " + command, p2)
        self.assertNotIn("sudo -n discovery-stateful-adguard", p2)
        self.assertNotIn("sudo -n cmp", p2)


if __name__ == "__main__":
    unittest.main()
