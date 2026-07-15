import copy
import importlib.util
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "modules/hosts/discovery/_stateful-swag-transition.py"
NIX_PACKAGE = ROOT / "modules/hosts/discovery/stateful-stack-ops.nix"


def load():
    spec = importlib.util.spec_from_file_location("swag_transition", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fixture():
    mount = [{"source": "/home/erik/servarr/machines/discovery/config/swag", "target": "/config", "type": "bind"}]
    common = {"compose_project": "networking", "compose_working_dir": "/home/erik/servarr/machines/discovery", "mounts": mount}
    return {
        "attempt_01": {"inventory_sha256": "35c294e9fe74e8b824df7aa8161693bfd555f09b97d1ef36b58a280d08d521e7", "manifest_sha256": "ee7861b9789f08a6fb0319ba931760054625d3e1cabe03bf43443560db3daee7", "retained": {name: {"path": path, "sha256": digit * 64} for name, path, digit in [
            ("approved_inventory", "/var/lib/stateful-stack-migrations/p1-swag/approved-inventory.json", "1"), ("archive", "/var/lib/stateful-stack-migrations/p1-swag/swag-config.tar.zst", "2"), ("archive_checksum", "/var/lib/stateful-stack-migrations/p1-swag/swag-config.tar.zst.sha256", "3"), ("authorization", "/var/lib/stateful-stack-migrations/p1-swag/authorization.json", "4"), ("ledger", "/var/lib/stateful-stack-migrations/p1-swag/ledger.json", "5")]} | {"snapshot": {"path": "/home/.snapshots/stateful-stack-p1-swag", "uuid": "99999999-9999-0999-0999-999999999999"}}},
        "attempt_02": {"manifest_sha256": "d8317282ce3f4716491c0c6a33c354c6dea12d4a02880cc8e3d6650bf3383fad", "observation_sha256": "c1696360b1feb06ddc02059605912a3d2ea2ec6f2fc3f8d7b9d2330eba9db303", "top_level_entries": ["authorization.json", "observation.json", "phases", "post-runtime.json"], "phase_markers": ["init-complete", "swag-complete"], "artifacts": {name: {"path": f"/var/lib/stateful-stack-migrations/p1-swag/attempt-02/{file}", "sha256": digit * 64} for name, file, digit in [("authorization", "authorization.json", "6"), ("observation", "observation.json", "7"), ("post_runtime", "post-runtime.json", "8")]}},
        "credential": {"device": 41, "inode": 42, "gid": 100, "mode": "0644", "path": "/home/erik/servarr/machines/discovery/config/swag/dns-conf/cloudflare.ini", "regular": True, "symlink": False, "uid": 1000},
        "runtime": {"containers": [dict(common, name="swag", compose_service="swag", id="a"*64, image_id="sha256:"+"b"*64, image_ref="lscr.io/linuxserver/swag:5.6.0-ls467@sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d", state="running"), dict(common, name="swag-init", compose_service="swag-init", id="c"*64, image_id="sha256:"+"d"*64, image_ref="busybox:1.38@sha256:fd8d9aa63ba2f0982b5304e1ee8d3b90a210bc1ffb5314d980eb6962f1a9715d", state="exited")]},
        "servarr": {"commit": "701c0efc23c5b0cc3fb152dd00f21dcb9a72cfc1", "compose_file": "/home/erik/servarr/machines/discovery/networking.yml", "render_sha256": "e"*64, "target_commit": "b676063eafa53c00947c458d631493f98349f63c", "target_render_sha256": "f"*64},
    }


class TransitionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.m = load()

    def test_exact_value_free_deterministic_contract(self):
        obs = fixture(); env = self.m.envelope(self.m.plan(obs))
        self.assertEqual(env, self.m.envelope(self.m.plan(copy.deepcopy(obs))))
        self.m.verify(obs, env)
        self.assertEqual(env["manifest"]["actions"], self.m.ACTIONS)
        rendered = str(env).lower()
        for forbidden in ("token", "password", "secret_value", "content", "size", "hash"):
            self.assertNotIn(forbidden, rendered)

    def test_every_identity_and_shape_drift_rejected(self):
        obs = fixture(); auth = self.m.envelope(self.m.plan(obs))
        paths = [("credential", "inode"), ("credential", "gid"), ("runtime", "containers", 0, "id"), ("servarr", "render_sha256"), ("attempt_02", "phase_markers"), ("attempt_02", "top_level_entries"), ("attempt_01", "retained", "ledger", "sha256")]
        for path in paths:
            changed=copy.deepcopy(obs); node=changed
            for key in path[:-1]: node=node[key]
            node[path[-1]]=[] if isinstance(node[path[-1]], list) else (999 if isinstance(node[path[-1]], int) else "0"*64)
            with self.subTest(path=path), self.assertRaises(self.m.Drift): self.m.verify(changed, auth)

    def test_executor_is_exact_metadata_and_lifecycle_transition_only(self):
        source=SCRIPT.read_text()
        for required in ("O_NOFOLLOW", "os.fstat", "os.fchown", "os.fchmod", "os.fsync", "RENAME_NOREPLACE", "servarr-repository.lock", "--force-recreate", "swag-init", '"nginx","-t"', "certbot", "target_render_sha256"):
            self.assertIn(required, source)
        for forbidden in ("docker system prune", "docker volume rm", "git pull", "shutil.rmtree", "read_text()"):
            self.assertNotIn(forbidden, source)
        self.assertNotIn("FETCH_HEAD", source)
        self.assertIn('"refs/heads/main:refs/remotes/origin/main"', source)
        self.assertIn('"rev-parse","origin/main"', source)

    def test_python_wrappers_are_directly_executable(self):
        package = NIX_PACKAGE.read_text()
        self.assertEqual(package.count('writeShellScriptBin "discovery-stateful-swag-'), 2)
        self.assertNotIn('writeScriptBin "discovery-stateful-swag-', package)

    def test_resumable_phase_contract_and_idempotent_gate_are_explicit(self):
        manifest=self.m.plan(fixture())
        self.assertEqual(manifest["phases"], ["repo-target","init-complete","metadata-complete","swag-complete","validated"])
        self.assertEqual(set(manifest["state_machine"]),set(manifest["phases"]))
        self.assertEqual(manifest["approval_scope"],{"compose_project":"networking","services":["swag-init","swag"]})
        self.assertIn("rewritten-by-swag-init-from-runtime-vault-env",manifest["credential"]["source_contract"])
        source=SCRIPT.read_text()
        for phase in manifest["phases"]:
            self.assertIn(f'mark_phase("{phase}")',source)
        self.assertLess(source.index('if "validated" in phases'),source.index('compose=['))
        self.assertIn("validate_completed",source)
        self.assertIn("both container identities must change",source)

    def test_every_monotonic_phase_prefix_requires_its_evidence(self):
        original=self.m.TRANSITION
        try:
            with tempfile.TemporaryDirectory() as directory:
                self.m.TRANSITION=pathlib.Path(directory)/"transition"
                self.m.TRANSITION.mkdir(); (self.m.TRANSITION/"phases").mkdir()
                (self.m.TRANSITION/"authorization.json").touch(); (self.m.TRANSITION/"observation.json").touch()
                artifacts={"init-complete":"init-state.json","metadata-complete":"metadata-state.json","swag-complete":"final-runtime.json"}
                for phase in self.m.PHASES:
                    if phase in artifacts: (self.m.TRANSITION/artifacts[phase]).touch()
                    if phase=="validated":
                        (self.m.TRANSITION/"kindle.png").touch(); (self.m.TRANSITION/"result.json").touch()
                    (self.m.TRANSITION/"phases"/phase).mkdir()
                    self.assertEqual(self.m.exact_phase_prefix(),set(self.m.PHASES[:self.m.PHASES.index(phase)+1]))
                (self.m.TRANSITION/"unknown").touch()
                with self.assertRaises(self.m.Drift): self.m.exact_phase_prefix()
        finally: self.m.TRANSITION=original

    def test_phase_dispatch_never_compares_completed_states_to_pre_runtime(self):
        cases={
            ():"pre",
            ("repo-target",):"pre",
            ("repo-target","init-complete"):"init",
            ("repo-target","init-complete","metadata-complete"):"init",
            ("repo-target","init-complete","metadata-complete","swag-complete"):"final",
            tuple(self.m.PHASES):"final",
        }
        for phases,expected in cases.items():
            with self.subTest(phases=phases): self.assertEqual(self.m.runtime_validation_phase(set(phases)),expected)
        source=SCRIPT.read_text()
        validated=source.index('if "validated" in phases')
        init_compare=source.index('runtime_validation_phase(phases)=="init"')
        self.assertLess(validated,init_compare)


if __name__ == "__main__": unittest.main()
