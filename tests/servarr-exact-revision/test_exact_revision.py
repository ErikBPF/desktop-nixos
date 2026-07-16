import hashlib
import fcntl
import importlib.util
import json
import pathlib
import subprocess
import tempfile
import threading
import time
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
HELPER = ROOT / "modules/server/_servarr-exact-revision.py"
FORWARD = "9969e35dca0cfb49a68bda3ba10156667cd4b53f"
ROLLBACK = "b676063eafa53c00947c458d631493f98349f63c"


def load():
    spec = importlib.util.spec_from_file_location("exact_revision", HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git(repo, *args):
    return subprocess.run(
        ["git", "-C", str(repo), *args], check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout.strip()


def digest(value):
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


class RepoFixture:
    def __init__(self, root):
        self.root = pathlib.Path(root)
        self.remote = self.root / "remote.git"
        self.source = self.root / "source"
        self.work = self.root / "work"
        subprocess.run(["git", "init", "--bare", str(self.remote)], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        subprocess.run(["git", "init", str(self.source)], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        git(self.source, "config", "user.name", "fixture")
        git(self.source, "config", "user.email", "fixture@example.invalid")
        git(self.source, "remote", "add", "origin", str(self.remote))
        machine = self.source / "machines/discovery"
        machine.mkdir(parents=True)
        (machine / ".env.sops").write_text("encrypted-v1\n")
        (machine / "networking.yml").write_text("services: {}\n")
        git(self.source, "add", ".")
        git(self.source, "commit", "-m", "rollback")
        self.rollback = git(self.source, "rev-parse", "HEAD")
        (machine / "networking.yml").write_text("services: {adguard: {}}\n")
        git(self.source, "add", ".")
        git(self.source, "commit", "-m", "forward")
        self.forward = git(self.source, "rev-parse", "HEAD")
        git(self.source, "branch", "-M", "main")
        git(self.source, "push", "-u", "origin", "main")
        subprocess.run(["git", "clone", str(self.remote), str(self.work)], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        git(self.work, "checkout", "main")


class ExactRevisionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m = load()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.fx = RepoFixture(self.temp.name)
        self.m.FORWARD = self.fx.forward
        self.m.ROLLBACK = self.fx.rollback
        self.m.LOCK_PATH = pathlib.Path(self.temp.name) / "servarr-repository.lock"
        self.renderer = lambda repo, commit: hashlib.sha256((commit + ":render").encode()).hexdigest()

    def prefetch(self):
        output = pathlib.Path(self.temp.name) / "prefetch.json"
        envelope = self.m.prefetch(self.fx.work, output=output, renderer=self.renderer)
        self.assertEqual(json.loads(output.read_text()), envelope)
        self.prefetch_path = output
        return envelope

    def authorization(self, prefetch, selection="forward"):
        body = {
            "prefetch": {"path": str(self.prefetch_path.resolve()), "sha256": hashlib.sha256(self.prefetch_path.read_bytes()).hexdigest()},
            "selected": prefetch["contract"][selection],
            "selection": selection,
            "version": 1,
        }
        return {"authorization": body, "authorization_sha256": digest(body)}

    def test_prefetch_fetches_and_binds_exact_published_ancestry_and_trees(self):
        evidence = self.prefetch()
        self.assertEqual(evidence["evidence"]["fetched_origin_main"], self.fx.forward)
        self.assertEqual(evidence["evidence"]["forward"]["commit"], self.fx.forward)
        self.assertEqual(evidence["evidence"]["rollback"]["commit"], self.fx.rollback)
        self.assertTrue(evidence["evidence"]["objects_present"])
        self.assertRegex(evidence["evidence"]["forward"]["tree"], r"^[0-9a-f]{40}$")
        self.assertRegex(evidence["evidence"]["forward"]["render_sha256"], r"^[0-9a-f]{64}$")
        self.assertNotIn(str(self.temp.name), json.dumps(evidence))

    def test_prefetch_rejects_unpublished_nonancestor_malformed_and_extra_schema(self):
        original_forward, original_rollback = self.m.FORWARD, self.m.ROLLBACK
        try:
            self.m.FORWARD = "f" * 40
            with self.assertRaises(self.m.ContractError): self.m.prefetch(self.fx.work, renderer=self.renderer)
            git(self.fx.source, "checkout", "--orphan", "foreign")
            (self.fx.source / "foreign").write_text("x")
            git(self.fx.source, "add", "foreign")
            git(self.fx.source, "commit", "-m", "foreign")
            foreign = git(self.fx.source, "rev-parse", "HEAD")
            git(self.fx.source, "push", "origin", "foreign")
            self.m.FORWARD, self.m.ROLLBACK = original_forward, foreign
            with self.assertRaises(self.m.ContractError): self.m.prefetch(self.fx.work, renderer=self.renderer)
        finally:
            self.m.FORWARD, self.m.ROLLBACK = original_forward, original_rollback
        valid = self.prefetch()
        for changed in (
            {**valid, "extra": True},
            {**valid, "evidence_sha256": "0" * 64},
            {"evidence": valid["evidence"]},
        ):
            with self.assertRaises(self.m.ContractError): self.m.validate_prefetch(changed)
        changed = json.loads(json.dumps(valid))
        changed["evidence"]["forward"]["render_sha256"] = "0" * 64
        changed["evidence_sha256"] = digest(changed["evidence"])
        with self.assertRaises(self.m.ContractError): self.m.validate_prefetch(changed)

    def test_activate_exact_selection_no_network_and_auth_drift_before_reset(self):
        prefetch = self.prefetch()
        auth = self.authorization(prefetch)
        calls = []
        runner = self.m.GitRunner(observer=lambda argv: calls.append(tuple(argv)))
        result = self.m.activate(self.fx.work, "forward", prefetch, auth, prefetch_path=self.prefetch_path, runner=runner)
        self.assertEqual(git(self.fx.work, "rev-parse", "HEAD"), self.fx.forward)
        self.assertEqual(result["evidence"]["head"], self.fx.forward)
        self.assertFalse(any("fetch" in argv for argv in calls))
        before = git(self.fx.work, "rev-parse", "HEAD")
        bad = json.loads(json.dumps(auth)); bad["authorization"]["selection"] = "rollback"
        with self.assertRaises(self.m.ContractError):
            self.m.activate(self.fx.work, "forward", prefetch, bad, prefetch_path=self.prefetch_path, runner=runner)
        self.assertEqual(git(self.fx.work, "rev-parse", "HEAD"), before)
        # Parsed evidence alone is insufficient: activation re-reads exact bytes.
        self.prefetch_path.write_text("{}\n")
        with self.assertRaises(self.m.ContractError):
            self.m.activate(self.fx.work, "forward", prefetch, auth, prefetch_path=self.prefetch_path, runner=runner)
        self.assertEqual(git(self.fx.work, "rev-parse", "HEAD"), before)
        with self.assertRaises(self.m.ContractError):
            self.m.activate(self.fx.work, "main", prefetch, auth, prefetch_path=self.prefetch_path, runner=runner)

    def test_activate_idempotent_pin_atomic_and_decrypt_only_when_blob_changed(self):
        prefetch = self.prefetch(); auth = self.authorization(prefetch, "rollback")
        decrypts = []
        class Decrypt:
            def prepare(inner, repo, commit): decrypts.append("prepare"); return "prepared"
            def install(inner, prepared): decrypts.append("install")
        first = self.m.activate(self.fx.work, "rollback", prefetch, auth, prefetch_path=self.prefetch_path,
                                decryptor=Decrypt())
        second = self.m.activate(self.fx.work, "rollback", prefetch, auth, prefetch_path=self.prefetch_path,
                                 decryptor=Decrypt())
        pin = json.loads((self.fx.work / ".deploy-commit").read_text())
        self.assertEqual(pin, self.m._pin_envelope(prefetch["contract"]["rollback"], "rollback"))
        self.assertFalse(first["evidence"]["encrypted_blob_changed"])
        self.assertTrue(second["evidence"]["idempotent"])
        self.assertEqual(decrypts, [])
        # A target whose encrypted blob differs invokes only the injected decryptor.
        git(self.fx.source, "checkout", "main")
        env = self.fx.source / "machines/discovery/.env.sops"
        env.write_text("encrypted-v2\n"); git(self.fx.source, "add", str(env)); git(self.fx.source, "commit", "-m", "env")
        changed = git(self.fx.source, "rev-parse", "HEAD")
        git(self.fx.source, "push", "origin", "main")
        git(self.fx.work, "reset", "--hard", self.fx.rollback)
        self.m.FORWARD = changed
        prefetch2 = self.m.prefetch(self.fx.work, output=self.prefetch_path, renderer=self.renderer)
        self.m.activate(self.fx.work, "forward", prefetch2, self.authorization(prefetch2), prefetch_path=self.prefetch_path, decryptor=Decrypt())
        self.assertEqual(decrypts, ["prepare", "install"])

    def test_decrypt_prepare_failure_leaves_head_pin_and_environment_unchanged(self):
        prefetch = self.prefetch(); auth = self.authorization(prefetch, "rollback")
        pin = self.fx.work / ".deploy-commit"; pin.write_text(self.fx.forward + "\n")
        env = self.fx.work / "machines/discovery/.env"; env.write_text("old-runtime\n")
        class Failure:
            def prepare(self, repo, commit): raise RuntimeError("injected")
            def install(self, prepared): raise AssertionError("must not install")
        before = (git(self.fx.work, "rev-parse", "HEAD"), pin.read_bytes(), env.read_bytes())
        # Force the fixture's encrypted blobs to differ for this contract test.
        original = self.m._blob
        self.m._blob = lambda runner, repo, revision: revision
        try:
            with self.assertRaises(RuntimeError):
                self.m.activate(self.fx.work, "rollback", prefetch, auth,
                                prefetch_path=self.prefetch_path, decryptor=Failure())
        finally: self.m._blob = original
        self.assertEqual((git(self.fx.work, "rev-parse", "HEAD"), pin.read_bytes(), env.read_bytes()), before)

    def test_install_and_pin_failures_restore_head_tree_pin_and_environment(self):
        prefetch = self.prefetch(); auth = self.authorization(prefetch, "rollback")
        pin = self.fx.work / ".deploy-commit"; pin.write_text(self.fx.forward + "\n")
        env = self.fx.work / "machines/discovery/.env"; env.write_bytes(b"prior-runtime\n")
        env.chmod(0o640)
        before = (git(self.fx.work, "rev-parse", "HEAD"),
                  git(self.fx.work, "show", "-s", "--format=%T", "HEAD"),
                  pin.read_bytes(), env.read_bytes(), env.stat().st_mode & 0o777)
        class InstallFailure:
            def prepare(self, repo, commit): return "prepared-fixture"
            def install(self, prepared): env.write_bytes(b"partial-new-runtime\n"); raise RuntimeError("install")
        original_blob = self.m._blob; self.m._blob = lambda runner, repo, revision: revision
        try:
            with self.assertRaises(RuntimeError):
                self.m.activate(self.fx.work, "rollback", prefetch, auth,
                                prefetch_path=self.prefetch_path, decryptor=InstallFailure())
        finally: self.m._blob = original_blob
        self.assertEqual((git(self.fx.work, "rev-parse", "HEAD"),
                          git(self.fx.work, "show", "-s", "--format=%T", "HEAD"),
                          pin.read_bytes(), env.read_bytes(), env.stat().st_mode & 0o777), before)

        class InstallSuccess:
            def prepare(self, repo, commit): return "prepared-fixture"
            def install(self, prepared): env.write_bytes(b"new-runtime\n")
        original_write = self.m._atomic_json
        def fail_pin(path, value):
            if pathlib.Path(path).name == ".deploy-commit": raise OSError("pin")
            return original_write(path, value)
        self.m._blob = lambda runner, repo, revision: revision
        self.m._atomic_json = fail_pin
        try:
            with self.assertRaises(OSError):
                self.m.activate(self.fx.work, "rollback", prefetch, auth,
                                prefetch_path=self.prefetch_path, decryptor=InstallSuccess())
        finally:
            self.m._blob = original_blob; self.m._atomic_json = original_write
        self.assertEqual((git(self.fx.work, "rev-parse", "HEAD"),
                          git(self.fx.work, "show", "-s", "--format=%T", "HEAD"),
                          pin.read_bytes(), env.read_bytes(), env.stat().st_mode & 0o777), before)

    def test_partial_pin_failure_removes_new_env_and_pin_when_previously_absent(self):
        prefetch = self.prefetch(); auth = self.authorization(prefetch, "rollback")
        pin = self.fx.work / ".deploy-commit"
        env = self.fx.work / "machines/discovery/.env"
        self.assertFalse(pin.exists()); self.assertFalse(env.exists())
        class Install:
            def prepare(self, repo, commit): return "prepared-fixture"
            def install(self, prepared): env.write_bytes(b"temporary-runtime\n")
        original_blob, original_write = self.m._blob, self.m._atomic_json
        self.m._blob = lambda runner, repo, revision: revision
        def partial_pin(path, value):
            original_write(path, value)
            raise OSError("after pin replace")
        self.m._atomic_json = partial_pin
        before = git(self.fx.work, "rev-parse", "HEAD")
        try:
            with self.assertRaises(OSError):
                self.m.activate(self.fx.work, "rollback", prefetch, auth,
                                prefetch_path=self.prefetch_path, decryptor=Install())
        finally:
            self.m._blob, self.m._atomic_json = original_blob, original_write
        self.assertEqual(git(self.fx.work, "rev-parse", "HEAD"), before)
        self.assertFalse(pin.exists()); self.assertFalse(env.exists())

    def test_activation_rechecks_local_publication_before_reset_and_cli_owner(self):
        prefetch = self.prefetch(); auth = self.authorization(prefetch)
        before = git(self.fx.work, "rev-parse", "HEAD")
        git(self.fx.work, "update-ref", "refs/remotes/origin/main", self.fx.rollback)
        with self.assertRaises(self.m.ContractError):
            self.m.activate(self.fx.work, "forward", prefetch, auth,
                            prefetch_path=self.prefetch_path)
        self.assertEqual(git(self.fx.work, "rev-parse", "HEAD"), before)
        original = self.m.REPOSITORY; self.m.REPOSITORY = self.fx.work
        try:
            with mock.patch.object(self.m.os, "geteuid", return_value=self.fx.work.stat().st_uid + 1):
                with self.assertRaises(self.m.ContractError): self.m._require_repository_owner()
        finally: self.m.REPOSITORY = original

    def test_shared_delivery_lock_blocks_then_locked_ref_recheck_rejects_toctou(self):
        prefetch = self.prefetch(); auth = self.authorization(prefetch)
        entered_git = threading.Event(); outcome = []
        runner = self.m.GitRunner(observer=lambda argv: entered_git.set())
        lock_path = self.m.LOCK_PATH
        with lock_path.open("a+") as delivery_lock:
            fcntl.flock(delivery_lock, fcntl.LOCK_EX)
            thread = threading.Thread(
                target=lambda: outcome.append(self._activation_outcome(prefetch, auth, runner)),
                daemon=True,
            )
            thread.start()
            self.assertFalse(entered_git.wait(0.2), "activation passed delivery lock")
            git(self.fx.work, "update-ref", "refs/remotes/origin/main", self.fx.rollback)
        thread.join(5)
        self.assertFalse(thread.is_alive())
        self.assertEqual(outcome, ["ContractError"])
        self.assertEqual(git(self.fx.work, "rev-parse", "HEAD"), self.fx.forward)

    def _activation_outcome(self, prefetch, auth, runner):
        try:
            self.m.activate(self.fx.work, "forward", prefetch, auth,
                            prefetch_path=self.prefetch_path, runner=runner)
        except Exception as error:
            return type(error).__name__
        return "activated"

    def test_verify_is_read_only_and_contract_declares_pin_precedence(self):
        prefetch = self.prefetch(); auth = self.authorization(prefetch)
        self.m.activate(self.fx.work, "forward", prefetch, auth, prefetch_path=self.prefetch_path)
        before = git(self.fx.work, "status", "--porcelain=v1", "--untracked-files=all")
        result = self.m.verify(self.fx.work, "forward", prefetch)
        after = git(self.fx.work, "status", "--porcelain=v1", "--untracked-files=all")
        self.assertEqual(before, after)
        self.assertEqual(result["evidence"]["status"], "verified")
        pin_path = self.fx.work / ".deploy-commit"
        pin = json.loads(pin_path.read_text()); pin["extra"] = True
        pin_path.write_text(json.dumps(pin))
        with self.assertRaises(self.m.ContractError):
            self.m.verify(self.fx.work, "forward", prefetch)
        self.assertEqual(self.m.pin_precedence_contract(), {
            "precedence": [".deploy-commit", ".deploy-branch", "default_branch"],
            "unpin_supported": False,
            "version": 1,
        })

    def test_source_has_no_shell_eval_or_secret_output_surface(self):
        source = HELPER.read_text().lower()
        for token in ("shell=true", "os.system", "eval(", "print(env", "cat .env"):
            self.assertNotIn(token, source)


if __name__ == "__main__":
    unittest.main()
