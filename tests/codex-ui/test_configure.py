"""The UI update preserves mutable Codex configuration and file permissions."""

import importlib.util
from pathlib import Path
import stat
import tempfile
import tomllib
import unittest


SOURCE = Path(__file__).resolve().parents[2] / "scripts/configure-codex-ui.py"
if SOURCE.exists():
    spec = importlib.util.spec_from_file_location("configure_codex_ui", SOURCE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    configure = module.configure
else:
    def configure(path):
        pass

ITEMS = ["five-hour-limit", "weekly-limit", "context-remaining", "model-with-reasoning"]


class ConfigureUI(unittest.TestCase):
    def test_retires_headroom_even_when_ui_is_already_configured(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.toml"
            configure(path)
            path.write_text('openai_base_url = "http://127.0.0.1:8788/v1"\n' + path.read_text())
            configure(path)
            self.assertNotIn("openai_base_url", tomllib.loads(path.read_text()))
            identity = (path.stat().st_ino, path.stat().st_mtime_ns)
            configure(path)
            self.assertEqual((path.stat().st_ino, path.stat().st_mtime_ns), identity)

    def test_preserves_other_explicit_endpoints(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.toml"
            path.write_text('openai_base_url = "https://api.openai.com/v1"\n')
            configure(path)
            self.assertEqual(tomllib.loads(path.read_text())["openai_base_url"], "https://api.openai.com/v1")

    def test_preserves_settings_comments_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.toml"
            path.write_text('# model stays selected\nmodel = "gpt-6-astra"\n[tui]\n# quota first\nstatus_line = ["git-branch"]\nnotifications = false\nauto_recap = true\n[tools.update_plan]\nenabled = false\n[tools.sleep]\nenabled = true\n[features]\nexample = true\n')
            path.chmod(0o600)
            configure(path)
            content = path.read_text()
            parsed = tomllib.loads(content)
            self.assertEqual(parsed["tui"]["status_line"], ITEMS)
            self.assertFalse(parsed["tui"]["auto_recap"])
            self.assertTrue(parsed["tools"]["update_plan"]["enabled"])
            self.assertTrue(parsed["tools"]["sleep"]["enabled"])
            self.assertEqual(parsed["model"], "gpt-6-astra")
            self.assertFalse(parsed["tui"]["notifications"])
            self.assertTrue(parsed["features"]["example"])
            self.assertIn("# model stays selected", content)
            self.assertIn("# quota first", content)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            identity = (path.stat().st_ino, path.stat().st_mtime_ns)
            configure(path)
            self.assertEqual((path.stat().st_ino, path.stat().st_mtime_ns), identity)

    def test_adds_missing_tui_table(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.toml"
            path.write_text('model = "gpt-6-astra"\n')
            configure(path)
            self.assertEqual(tomllib.loads(path.read_text()), {"model": "gpt-6-astra", "tui": {"status_line": ITEMS, "auto_recap": False}, "tools": {"update_plan": {"enabled": True}}})

    def test_creates_missing_configuration_privately(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".codex" / "config.toml"
            configure(path)
            self.assertTrue(path.is_file())
            self.assertEqual(tomllib.loads(path.read_text()), {"tui": {"status_line": ITEMS, "auto_recap": False}, "tools": {"update_plan": {"enabled": True}}})
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
