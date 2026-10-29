#!/usr/bin/env python3
"""Exercise rendered cache access rules against disposable loopback nginx."""

import argparse
import http.client
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import time

from test_contract import WRITERS, cache_config


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--nginx", type=Path, required=True)
    parser.add_argument("--module", type=Path)
    args = parser.parse_args()
    extra = cache_config(args.module)["extra"]
    with tempfile.TemporaryDirectory(prefix="sccache-writers-") as folder:
        root = Path(folder)
        cache = root / "cache"
        cache.mkdir()
        (cache / "readable").write_bytes(b"synthetic-cache-entry")
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        config = root / "nginx.conf"
        config.write_text(f"""
daemon off;
master_process off;
pid {root}/nginx.pid;
error_log {root}/error.log;
events {{}}
http {{
  access_log off;
  client_body_temp_path {root}/body;
  server {{
    listen 127.0.0.1:{port};
    location / {{
      root {cache};
      {extra}
    }}
  }}
}}
""")
        subprocess.run(
            [str(args.nginx), "-t", "-p", str(root), "-c", str(config)],
            check=True, capture_output=True,
        )
        process = subprocess.Popen(
            [str(args.nginx), "-p", str(root), "-c", str(config)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        results = []

        def request(source, method, path, body=None, headers=None):
            connection = http.client.HTTPConnection(
                "127.0.0.1", port, timeout=3, source_address=(source, 0),
            )
            try:
                connection.request(method, path, body=body, headers=headers or {})
                response = connection.getresponse()
                return response.status, response.read()
            finally:
                connection.close()

        def check(role, source, method, path, expected, body=None, headers=None):
            status, payload = request(source, method, path, body, headers)
            passed = status == expected
            results.append({"role": role, "method": method, "status": status,
                            "expected": expected, "passed": passed})
            assert passed, f"{role} {method}: expected {expected}, got {status}"
            return payload

        try:
            deadline = time.monotonic() + 5
            while True:
                if process.poll() is not None:
                    raise RuntimeError("nginx exited before readiness")
                try:
                    request("127.0.0.1", "GET", "/readable")
                    break
                except OSError:
                    if time.monotonic() >= deadline:
                        raise
                    time.sleep(0.05)
            for role, source in WRITERS.items():
                path = "/" + role
                check(role, source, "PUT", path, 201, b"synthetic")
                assert check(role, source, "GET", path, 200) == b"synthetic"
                check(role, source, "HEAD", path, 200)
                check(role, source, "COPY", path, 204,
                      headers={"Destination": f"http://127.0.0.1:{port}{path}-copy"})
                check(role, source, "MOVE", path + "-copy", 204,
                      headers={"Destination": f"http://127.0.0.1:{port}{path}-moved"})
                assert check(role, source, "GET", path + "-moved", 200) == b"synthetic"
                check(role, source, "DELETE", path + "-moved", 204)
                check(role, source, "DELETE", path, 204)
                check(role, source, "MKCOL", path + "/", 201)
                check(role, source, "DELETE", path + "/", 204)
            for role, source in [("discovery", "127.0.0.6"), ("unapproved", "127.0.0.7")]:
                assert check(role, source, "GET", "/readable", 200) == b"synthetic-cache-entry"
                check(role, source, "HEAD", "/readable", 200)
                for method in ["PUT", "DELETE", "MKCOL", "COPY", "MOVE"]:
                    check(role, source, method, "/readable", 403, b"denied",
                          {"Destination": f"http://127.0.0.1:{port}/copied"})
                check(role, source, "PUT", "/readable", 403, b"denied",
                      {"X-Forwarded-For": WRITERS["endeavour"], "X-Real-IP": WRITERS["endeavour"]})
            assert (cache / "readable").read_bytes() == b"synthetic-cache-entry"
            assert not (cache / "copied").exists()
            check("local-maintenance", "127.0.0.1", "PUT", "/local", 201, b"synthetic")
            check("local-maintenance", "127.0.0.1", "DELETE", "/local", 204)
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        print(json.dumps({"scope": "synthetic loopback addresses; actual nginx and rendered leaf",
                          "cases": results, "passed": len(results)}, indent=2))
        print("SCCACHE_WRITER_BOUNDARY_OK")


if __name__ == "__main__":
    main()
