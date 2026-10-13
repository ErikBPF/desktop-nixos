"""Exercise an exact V2 binary's auth boundary without user state or models."""
import base64
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path


def main():
    binary, expected_version = sys.argv[1:]
    parent = Path.home() / ".local/share/opencode-v2/tmp/opencode"
    parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="backend-auth-", dir=parent) as directory:
        root = Path(directory)
        env = {"PATH": os.environ["PATH"], "HOME": directory,
               "OPENCODE_PASSWORD": "disposable-auth-fixture"}
        for kind in ("CONFIG", "DATA", "STATE", "CACHE"):
            env[f"XDG_{kind}_HOME"] = str(root / kind.lower())
        env["OPENCODE_DB"] = str(root / "state/test.db")
        version = subprocess.check_output([binary, "--version"], env=env, text=True).strip()
        assert version == f"opencode v{expected_version}", (version, expected_version)
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        with (root / "server.log").open("w") as log:
            process = subprocess.Popen([binary, "serve", "--hostname", "127.0.0.1",
                                        "--port", str(port)], cwd=root, env=env,
                                       stdout=log, stderr=log)
            try:
                url = f"http://127.0.0.1:{port}/api/info"
                authorization = base64.b64encode(
                    b"opencode:disposable-auth-fixture").decode()
                request = urllib.request.Request(url, headers={
                    "Authorization": "Basic " + authorization})
                deadline = time.monotonic() + 20
                while True:
                    try:
                        with urllib.request.urlopen(request, timeout=2) as response:
                            info = json.load(response)
                        break
                    except urllib.error.URLError:
                        if process.poll() is not None or time.monotonic() > deadline:
                            raise RuntimeError("Disposable backend did not become healthy; private log retained only during test") from None
                        time.sleep(0.1)
                assert info["version"] == expected_version, info["version"]
                assert info["pid"] == process.pid, "Response came from a different process"
                client_info = json.loads(subprocess.check_output(
                    [binary, "api", "--server", f"http://127.0.0.1:{port}",
                     "get", "/api/info"], cwd=root, env=env, text=True, timeout=10))
                assert client_info["pid"] == process.pid, "Native client discovered the wrong server"
                try:
                    urllib.request.urlopen(url, timeout=2).close()
                except urllib.error.HTTPError as error:
                    code = error.code
                    error.close()
                    assert code == 401, code
                else:
                    raise AssertionError("Backend accepted an unauthenticated request")
            finally:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
    print(f"V2_AUTH_SMOKE_OK version={expected_version}; exact PID, native client, authenticated API, unauthenticated denial")


if __name__ == "__main__":
    main()
