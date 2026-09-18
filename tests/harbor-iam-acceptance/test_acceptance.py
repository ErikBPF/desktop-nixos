import base64
import json
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import ClassVar

ROOT = Path(__file__).parents[2]
SCRIPT = ROOT / "scripts" / "harbor-iam-acceptance.sh"

PROJECTS = ["dockerhub", "ghcr", "k8s", "langfuse", "library", "lscr", "quay", "risingwave"]
PASSWORD = "test-password"


class Handler(BaseHTTPRequestHandler):
    fixtures: ClassVar[dict] = {}

    def _json(self, payload):
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/application/o/harbor/.well-known/openid-configuration":
            self._json(self.fixtures["issuer"])
            return
        if path == "/jwks":
            self._json({"keys": []})
            return
        if path == "/api/v2.0/systeminfo":
            # Harbor serves systeminfo without authentication; mirror that here
            # because the LAN-independence gate is credential-free.
            self._json(self.fixtures["systeminfo"])
            return
        expected = "Basic " + base64.b64encode(f"admin:{PASSWORD}".encode()).decode()
        if self.headers.get("Authorization") != expected:
            self.send_response(401)
            self.end_headers()
            return
        if path == "/api/v2.0/configurations":
            self._json(self.fixtures["configuration"])
        elif path == "/api/v2.0/users":
            self._json(self.fixtures["users"])
        elif path.startswith("/api/v2.0/users/"):
            detail = self.fixtures["user_details"].get(path.rsplit("/", 1)[1])
            if detail is None:
                self.send_response(404)
                self.end_headers()
                return
            self._json(detail)
        elif path == "/api/v2.0/projects":
            self._json(self.fixtures["projects"])
        elif path.startswith("/api/v2.0/projects/"):
            self._json(self.fixtures["members"].get(path.split("/")[4], []))
        elif path == "/api/v2.0/robots":
            self._json(self.fixtures["robots"])
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *_args):
        pass


def default_fixtures():
    return {
        "systeminfo": {
            "auth_mode": "oidc_auth",
            "primary_auth_mode": False,
            "self_registration": False,
            "oidc_provider_name": "Authentik",
        },
        "configuration": {
            "oidc_name": {"value": "Authentik"},
            "oidc_admin_group": {"value": ""},
            "oidc_verify_cert": {"value": True},
            "oidc_groups_claim": {"value": "groups"},
            "oidc_user_claim": {"value": "preferred_username"},
            "oidc_auto_onboard": {"value": True},
            "oidc_scope": {"value": "openid,email,profile,offline_access,groups"},
            "oidc_client_secret": {"value": "omit-me"},
        },
        "users": [
            {"user_id": 1, "username": "admin", "sysadmin_flag": True},
            {"user_id": 2, "username": "erik", "sysadmin_flag": False},
        ],
        "user_details": {"2": {"user_id": 2, "oidc_user_meta": {"sub": "erik"}}},
        "projects": [
            {"project_id": index + 1, "name": name} for index, name in enumerate(PROJECTS)
        ],
        "members": {
            name: [
                {
                    "id": index + 1,
                    "project_id": index + 1,
                    "entity_name": "harbor-readers",
                    "entity_type": "g",
                    "role_name": "guest",
                }
            ]
            for index, name in enumerate(PROJECTS)
        },
        "robots": [
            {
                "id": 7,
                "name": "robot$desktop-nixos-kepler-harbor-reader",
                "level": "system",
                "secret": "omit-me",
                "permissions": [
                    {
                        "kind": "project",
                        "namespace": "*",
                        "access": [{"action": "pull", "resource": "repository"}],
                    }
                ],
            }
        ],
        "issuer": {},
    }


def run_acceptance(tmp_path, fixtures=None):
    fixtures = fixtures or default_fixtures()
    Handler.fixtures = fixtures
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        base = f"http://127.0.0.1:{server.server_address[1]}"
        fixtures["issuer"] = {
            "issuer": f"{base}/application/o/harbor/",
            "jwks_uri": f"{base}/jwks",
        }
        env_file = tmp_path / "harbor.env"
        env_file.write_text(f"HARBOR_ADMIN_USER=admin\nHARBOR_ADMIN_PASSWORD={PASSWORD}\n")
        env_file.chmod(0o600)
        completed = subprocess.run(
            [
                "bash",
                str(SCRIPT),
                "--url",
                base,
                "--issuer",
                f"{base}/application/o/harbor",
                "--env-file",
                str(env_file),
                "--projects",
                ",".join(PROJECTS),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    finally:
        server.shutdown()
    payload = json.loads(completed.stdout) if completed.stdout.strip() else {}
    return completed, payload


def gates(payload):
    return {gate["id"]: gate for gate in payload.get("gates", [])}


def test_default_acceptance_passes(tmp_path):
    completed, payload = run_acceptance(tmp_path)
    assert completed.returncode == 0, completed.stderr
    assert payload["result"] == "pass"
    assert payload["summary"] == {"passed": 17, "failed": 0}


def test_output_is_sanitized(tmp_path):
    completed, _ = run_acceptance(tmp_path)
    assert "omit-me" not in completed.stdout
    assert PASSWORD not in completed.stdout


def test_missing_guest_role_fails(tmp_path):
    fixtures = default_fixtures()
    fixtures["members"]["dockerhub"] = []
    completed, payload = run_acceptance(tmp_path, fixtures)
    assert completed.returncode == 2
    assert not gates(payload)["reader_group_guest_everywhere"]["pass"]


def test_pushing_reader_robot_fails(tmp_path):
    fixtures = default_fixtures()
    fixtures["robots"][0]["permissions"][0]["access"].append(
        {"action": "push", "resource": "repository"}
    )
    completed, payload = run_acceptance(tmp_path, fixtures)
    assert completed.returncode == 2
    assert not gates(payload)["reader_robots_pull_only"]["pass"]


def test_local_non_admin_user_fails(tmp_path):
    fixtures = default_fixtures()
    fixtures["users"].append({"user_id": 3, "username": "legacy", "sysadmin_flag": False})
    completed, payload = run_acceptance(tmp_path, fixtures)
    assert completed.returncode == 2
    assert gates(payload)["local_non_admin_users"]["observed"] == ["legacy"]


def test_admin_group_membership_fails(tmp_path):
    fixtures = default_fixtures()
    fixtures["members"]["library"].append(
        {
            "id": 9,
            "project_id": 5,
            "entity_name": "harbor-admins",
            "entity_type": "g",
            "role_name": "projectAdmin",
        }
    )
    completed, payload = run_acceptance(tmp_path, fixtures)
    assert completed.returncode == 2
    assert not gates(payload)["admin_group_unbound"]["pass"]


def test_script_never_disables_certificate_verification():
    script = SCRIPT.read_text()
    assert " --insecure" not in script
    assert " -k " not in script
