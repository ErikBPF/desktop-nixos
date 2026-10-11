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

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                self.rfile.read(int(self.headers.get("Content-Length", "0")))
                requests.append((self.headers.get("x-opencode-session"), self.headers.get("x-session-affinity")))
                self.send_response(400)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"error":{"message":"Synthetic stop after header capture","type":"invalid_request_error"}}')

            def log_message(self, *_args):
                pass

        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server, tempfile.TemporaryDirectory() as directory:
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
                env = {key: value for key, value in os.environ.items() if not key.startswith("OPENCODE_")}
                env.update({"XDG_CONFIG_HOME": str(root / "config"), "XDG_DATA_HOME": str(root / "data"),
                            "XDG_CACHE_HOME": str(root / "cache"), "XDG_STATE_HOME": str(root / "state"),
                            "OPENCODE_DISABLE_CLAUDE_CODE": "1", "OPENCODE_DISABLE_MODELS_FETCH": "1"})
                # v2 core already sends x-opencode-session for custom
                # providers, so the header appears with the plugin loaded and
                # unloaded; the plugin keeps the provider-scoped guarantee.
                for enabled in [False, True]:
                    with self.subTest(bridge_enabled=enabled):
                        requests.clear()
                        settings["plugins"] = [(ROOT / "modules/dev/opencode-plugins-v2/gateway-headers").as_uri()] if enabled else []
                        (config / "opencode.json").write_text(json.dumps(settings))
                        result = subprocess.run(["opencode", "run", "--format", "json", "Return OK."],
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
                        for actual, affinity in requests:
                            self.assertIn(affinity, sessions)
                            self.assertEqual(actual, affinity)
            finally:
                server.shutdown()
                thread.join()


if __name__ == "__main__":
    unittest.main()
