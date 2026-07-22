import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/server/orchestration.nix"


class UnitLifecycleTest(unittest.TestCase):
    def setUp(self):
        self.source = MODULE.read_text()

    def test_runtime_directory_settings_are_absent_without_a_profile(self):
        self.assertIn(
            "// lib.optionalAttrs (secretSpecProfile != null) {",
            self.source,
        )
        self.assertNotIn(
            'RuntimeDirectoryMode = lib.optionalString (secretSpecProfile != null) "0700";',
            self.source,
        )

    def test_stop_does_not_require_runtime_secret_projection(self):
        stop_script = self.source.split(
            'stopStack = pkgs.writeShellScript "stop-compose-${name}"', 1
        )[1].split("      in {", 1)[0]
        exec_stop = self.source.split("ExecStop =", 1)[1].split(";", 1)[0]
        self.assertIn("if secretSpecProfile == null", exec_stop)
        self.assertIn("legacyStop", exec_stop)
        self.assertIn("stopStack", exec_stop)
        self.assertIn("com.docker.compose.project=${name}", stop_script)
        self.assertNotIn("runtimeProvider", stop_script)
        self.assertNotIn("composeEnv", stop_script)


if __name__ == "__main__":
    unittest.main()
