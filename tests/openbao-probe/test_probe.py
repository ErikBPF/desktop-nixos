"""Run the deployed probe body against synthetic loopback HTTP responses."""
import http.server
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ProbeTest(unittest.TestCase):
    def test_authenticated_probe(self):
        source = (ROOT / "modules/hosts/discovery/vault.nix").read_text()
        script = source.split('writeShellScript "openbao-seal-probe" \'\'', 1)[1].split("        '';", 1)[0]
        token_value = "synthetic-canary-token"
        requests = []
        status = 200

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == "/v1/sys/seal-status":
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b'{"sealed":false}')
                else:
                    requests.append((self.path, self.headers.get("X-Vault-Token")))
                    self.send_response(status)
                    self.end_headers()
                    self.wfile.write(token_value.encode())

            def log_message(self, *_args):
                pass

        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                with tempfile.TemporaryDirectory() as directory:
                    path = Path(directory)
                    token = path / "token"
                    script = script.replace("${addr}", f"http://127.0.0.1:{server.server_port}")
                    script = script.replace("${pkgs.curl}/bin/curl", shutil.which("curl"))
                    script = script.replace("${jq}", shutil.which("jq"))
                    script = script.replace("${pkgs.coreutils}/bin/", "")
                    script = script.replace("/var/lib/node-exporter-textfile", directory)
                    script = script.replace("/run/vault-agent/token", str(token))
                    for status, present, expected in [(200, True, 1), (403, True, 0), (500, True, 0), (200, False, 0)]:
                        with self.subTest(status=status, token_present=present):
                            requests.clear()
                            if present:
                                token.write_text(token_value)
                                token.chmod(0o640)
                            else:
                                token.unlink()
                            before = int(time.time())
                            result = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertNotIn(token_value, result.stdout + result.stderr)
                            metrics = (path / "openbao_sealed.prom").read_text()
                            self.assertIn("openbao_sealed 0\n", metrics)
                            self.assertIn(f"openbao_authenticated_probe_success {expected}\n", metrics)
                            timestamp = int(next(line.split()[1] for line in metrics.splitlines()
                                                 if line.startswith("openbao_authenticated_probe_timestamp_seconds ")))
                            self.assertLessEqual(before, timestamp)
                            self.assertLessEqual(timestamp, int(time.time()))
                            self.assertEqual(requests, [("/v1/auth/token/lookup-self", token_value)] if present else [])
                            self.assertEqual((path / "openbao_sealed.prom").stat().st_mode & 0o777, 0o644)
                            self.assertFalse(list(path.glob(".openbao_sealed.*")))
            finally:
                server.shutdown()
                thread.join()


if __name__ == "__main__":
    unittest.main()
