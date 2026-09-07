"""Execute the shipped inline Python against a fake gateway, without credentials."""
import io
import json
from pathlib import Path
import textwrap
import unittest
import urllib.error
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/hosts/discovery/runtime-health.nix"
PROBE = textwrap.dedent(MODULE.read_text().split(
    'litellmPython = pkgs.writeText "litellm-semantic-probe.py" \'\'\n', 1
)[1].split("    '';", 1)[0])


class SemanticProbe(unittest.TestCase):
    def run_probe(self, health=None, completion=None):
        calls = []
        self.models = []

        def gateway(request, timeout):
            calls.append(request.full_url)
            if request.full_url.endswith("/health/readiness"):
                body = health if health is not None else {"status": "healthy", "db": "connected"}
            else:
                self.models.append(json.loads(request.data)["model"])
                body = completion if completion is not None else {"choices": [{"message": {"content": "OK"}}]}
            return io.StringIO(json.dumps(body))

        with patch.dict("os.environ", {"LITELLM_MASTER_KEY": "test-only"}), \
                patch("urllib.request.urlopen", side_effect=gateway):
            exec(compile(PROBE, str(MODULE), "exec"), {})
        return calls

    def test_paused_ha_does_not_prevent_real_promised_chat_completion(self):
        self.assertEqual(self.run_probe(), [
            "http://127.0.0.1:4000/health/readiness",
            "http://127.0.0.1:4000/v1/chat/completions",
        ])
        self.assertEqual(self.models, ["qwen-chat"])

    def test_database_failure_still_fails(self):
        with self.assertRaises(AssertionError):
            self.run_probe(health={"status": "healthy", "db": "disconnected"})

    def test_empty_completion_still_fails(self):
        with self.assertRaises(AssertionError):
            self.run_probe(completion={"choices": []})

    def test_gateway_unreachable_still_fails(self):
        with patch.dict("os.environ", {"LITELLM_MASTER_KEY": "test-only"}), \
                patch("urllib.request.urlopen", side_effect=urllib.error.URLError("unreachable")):
            with self.assertRaises(urllib.error.URLError):
                exec(compile(PROBE, str(MODULE), "exec"), {})


if __name__ == "__main__":
    unittest.main()
