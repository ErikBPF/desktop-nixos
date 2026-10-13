"""Capture actual OpenCode HTTP headers against a disposable loopback endpoint."""
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]


class GatewayHeaders(unittest.TestCase):
    def test_actual_client_session_header(self):
        requests = []
        managed = json.loads(subprocess.check_output([
            "nix", "eval", "--json",
            ".#nixosConfigurations.endeavour.config.home-manager.users.erik.programs.opencode.settings",
            "--apply", 'settings: { inherit (settings) plugins; workModel = settings.provider.work.models."deepseek-v4.1-flash"; }',
        ], cwd=ROOT, text=True))
        plugins = managed["plugins"]
        temporary_parent = Path.home() / ".local/share/opencode-v2/tmp/opencode"
        temporary_parent.mkdir(parents=True, exist_ok=True)

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
                requests.append((self.headers.get("x-opencode-session"), self.headers.get("x-session-affinity"), body))
                self.send_response(400)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"error":{"message":"Synthetic stop after header capture","type":"invalid_request_error"}}')

            def log_message(self, *_args):
                pass

        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server, tempfile.TemporaryDirectory(
                dir=temporary_parent) as directory:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                root = Path(directory)
                config = root / "config/opencode"
                config.mkdir(parents=True)
                repo = root / "repo"
                repo.mkdir()
                settings = {
                    "model": "litellm/synthetic", "enabled_providers": ["litellm"],
                    "provider": {"litellm": {"npm": "@ai-sdk/openai-compatible",
                        "options": {"baseURL": f"http://127.0.0.1:{server.server_port}/v1", "apiKey": "synthetic"},
                        "models": {"synthetic": {"name": "Synthetic", "limit": {"context": 10000, "output": 100}}}}},
                }
                env = {"PATH": os.environ["PATH"], "HOME": str(root)}
                env.update({"XDG_CONFIG_HOME": str(root / "config"), "XDG_DATA_HOME": str(root / "data"),
                            "XDG_CACHE_HOME": str(root / "cache"), "XDG_STATE_HOME": str(root / "state"),
                            "OPENCODE_DISABLE_CLAUDE_CODE": "1", "OPENCODE_DISABLE_MODELS_FETCH": "1"})
                # v2 core already sends x-opencode-session for custom
                # providers, so the header appears with the plugin loaded and
                # unloaded; the plugin keeps the provider-scoped guarantee.
                for enabled, work in [(False, False), (True, False), (True, True)]:
                    with self.subTest(bridge_enabled=enabled, work_gateway=work):
                        requests.clear()
                        if work:
                            settings = {
                                "model": "work/deepseek-v4.1-flash", "enabled_providers": ["work"],
                                "provider": {"work": {"npm": "@ai-sdk/openai-compatible",
                                    "options": {"baseURL": f"http://127.0.0.1:{server.server_port}/v1", "apiKey": "synthetic"},
                                    "models": {"deepseek-v4.1-flash": managed["workModel"]}}},
                            }
                        settings["plugins"] = plugins if enabled else []
                        (config / "opencode.json").write_text(json.dumps(settings))
                        result = subprocess.run([os.environ.get("OPENCODE_TEST_BINARY", "opencode"),
                                                  "run", "--standalone", "--format", "json",
                                                  "--title", "Synthetic header smoke", "Return OK."],
                                                cwd=repo, env=env, capture_output=True, text=True, timeout=90)
                        sessions = set()
                        for line in result.stdout.splitlines():
                            try:
                                event = json.loads(line)
                            except ValueError:
                                continue
                            if event.get("sessionID"):
                                sessions.add(event["sessionID"])
                        self.assertTrue(requests, "No loopback model request observed")
                        self.assertTrue(sessions, "No CLI session event observed")
                        for actual, affinity, body in requests:
                            self.assertIn(affinity, sessions)
                            self.assertEqual(actual, affinity)
                            if enabled:
                                self.assertIn("PONYTAIL MODE ACTIVE", json.dumps(body))
                            if work:
                                self.assertFalse("reasoning_effort" in body, "Work gateway rejects this parameter")
            finally:
                server.shutdown()
                thread.join()


if __name__ == "__main__":
    unittest.main()
