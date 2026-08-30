import base64
import hashlib
import json
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import ClassVar

ROOT = Path(__file__).parents[2]
SCRIPT = ROOT / "scripts/harbor-iam-preflight.sh"
BOOTSTRAP = ROOT / "scripts/bootstrap-authentik.sh"
RETIRE_BOOTSTRAP = ROOT / "scripts/retire-authentik-bootstrap.sh"
HASHER = ROOT / "scripts/authentik-password-hash.py"


class HarborHandler(BaseHTTPRequestHandler):
    users: ClassVar[list[dict]] = []

    def do_GET(self):
        expected = "Basic " + base64.b64encode(b"admin:test-password").decode()
        if self.headers.get("Authorization") != expected:
            self.send_response(401)
            self.end_headers()
            return
        payloads = {
            "/api/v2.0/systeminfo": {"auth_mode": "db_auth", "secret": "omit-me"},
            "/api/v2.0/configurations": {
                "auth_mode": {"value": "db_auth"},
                "oidc_client_secret": {"value": "omit-me"},
            },
            "/api/v2.0/users": self.users,
            "/api/v2.0/projects": [
                {"project_id": 1, "name": "library", "metadata": {"public": "true"}}
            ],
            "/api/v2.0/robots": [
                {
                    "id": 7,
                    "name": "robot$reader",
                    "disabled": False,
                    "secret": "omit-me",
                    "permissions": [],
                }
            ],
        }
        path = self.path.split("?", 1)[0]
        body = json.dumps(payloads[path]).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


def run_preflight(tmp_path, users):
    HarborHandler.users = users
    server = ThreadingHTTPServer(("127.0.0.1", 0), HarborHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env_file = tmp_path / "harbor.env"
    env_file.write_text(
        "HARBOR_ADMIN_USER=admin\nHARBOR_ADMIN_PASSWORD=test-password\n"
    )
    try:
        return subprocess.run(
            [
                "bash",
                str(SCRIPT),
                "--url",
                f"http://127.0.0.1:{server.server_port}",
                "--env-file",
                str(env_file),
            ],
            text=True,
            capture_output=True,
            check=False,
        )
    finally:
        server.shutdown()
        thread.join()
        server.server_close()


def test_preflight_redacts_api_secrets(tmp_path):
    result = run_preflight(
        tmp_path,
        [{"user_id": 1, "username": "admin", "sysadmin_flag": True}],
    )
    assert result.returncode == 0, result.stderr
    assert "omit-me" not in result.stdout
    assert "test-password" not in result.stdout
    evidence = json.loads(result.stdout)
    assert evidence["auth_mode"] == "db_auth"
    assert evidence["local_non_admin_users"] == []
    assert evidence["projects"] == [
        {"project_id": 1, "name": "library", "public": True}
    ]
    assert evidence["robots"][0]["name"] == "robot$reader"


def test_preflight_blocks_non_admin_local_users(tmp_path):
    result = run_preflight(
        tmp_path,
        [
            {"user_id": 1, "username": "admin", "sysadmin_flag": True},
            {"user_id": 2, "username": "local-user", "sysadmin_flag": False},
        ],
    )
    assert result.returncode == 2
    assert json.loads(result.stdout)["local_non_admin_users"] == ["local-user"]


def test_recipe_runs_the_redacting_wrapper_on_discovery():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("harbor-iam-preflight:", 1)[1].split("\n\n", 1)[0]
    assert "scripts/harbor-iam-preflight.sh" in recipe
    assert "sudo /run/current-system/sw/bin/bash -s --" in recipe
    assert "/run/vault-agent/harbor.env" in recipe


def test_authentik_bootstrap_handoff_check_is_value_free(tmp_path):
    handoff = tmp_path / "authentik-bootstrap.secrets.json"
    handoff.write_text(
        json.dumps(
            {
                "breakglass_password": "never-print-password",
                "bootstrap_token": "never-print-token-0123456789abcdef",
            }
        )
    )
    handoff.chmod(0o600)
    result = subprocess.run(
        ["bash", str(BOOTSTRAP), "--check", str(handoff)],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "authentik bootstrap handoff OK"
    assert "never-print" not in result.stdout + result.stderr
    assert handoff.exists()


def test_authentik_bootstrap_rejects_broad_file_mode(tmp_path):
    handoff = tmp_path / "authentik-bootstrap.secrets.json"
    handoff.write_text("{}")
    handoff.chmod(0o644)
    result = subprocess.run(
        ["bash", str(BOOTSTRAP), "--check", str(handoff)],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode != 0
    assert "mode 0600" in result.stderr


def test_authentik_bootstrap_rejects_extra_secret_keys(tmp_path):
    handoff = tmp_path / "authentik-bootstrap.secrets.json"
    handoff.write_text(
        json.dumps(
            {
                "breakglass_password": "never-print-password",
                "bootstrap_token": "never-print-token-0123456789abcdef",
                "unrelated_secret": "never-print-extra",
            }
        )
    )
    handoff.chmod(0o600)
    result = subprocess.run(
        ["bash", str(BOOTSTRAP), "--check", str(handoff)],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode != 0
    assert "never-print" not in result.stdout + result.stderr


def test_authentik_bootstrap_rejects_short_token(tmp_path):
    handoff = tmp_path / "authentik-bootstrap.secrets.json"
    handoff.write_text(
        json.dumps(
            {
                "breakglass_password": "never-print-password",
                "bootstrap_token": "short",
            }
        )
    )
    handoff.chmod(0o600)
    result = subprocess.run(
        ["bash", str(BOOTSTRAP), "--check", str(handoff)],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode != 0
    assert "short" not in result.stdout + result.stderr


def test_authentik_bootstrap_avoids_secret_process_arguments():
    source = BOOTSTRAP.read_text()
    assert "--from-file=AUTHENTIK_BOOTSTRAP_PASSWORD_HASH=" in source
    assert "--from-file=AUTHENTIK_BOOTSTRAP_TOKEN=" in source
    assert "--from-literal" not in source
    assert "export AUTHENTIK_BREAKGLASS_PASSWORD" not in source
    assert "authentik-password-hash.py" in source
    assert "sops --encrypt" in source
    assert 'rm -f -- "$handoff"' in source
    assert "create namespace authentik" in source
    assert source.index("create namespace authentik") < source.index(
        "create secret generic authentik-bootstrap"
    )


def test_authentik_password_hash_matches_django_format(tmp_path):
    password = tmp_path / "password"
    password.write_text("correct horse battery staple")
    result = subprocess.run(
        ["python3", str(HASHER), str(password)],
        text=True,
        capture_output=True,
        check=True,
    )
    algorithm, iterations, salt, encoded = result.stdout.strip().split("$")
    assert algorithm == "pbkdf2_sha256"
    assert iterations == "1000000"
    expected = base64.b64encode(
        hashlib.pbkdf2_hmac(
            "sha256", password.read_bytes(), salt.encode(), int(iterations)
        )
    ).decode()
    assert encoded == expected


def test_authentik_bootstrap_has_a_documented_entrypoint():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("bootstrap-authentik ", 1)[1].split("\n\n", 1)[0]
    assert "scripts/bootstrap-authentik.sh" in recipe


def test_authentik_retirement_handoff_check_is_value_free(tmp_path):
    handoff = tmp_path / "authentik-iac.secrets.json"
    handoff.write_text(
        json.dumps(
            {
                "token": "never-print-token-0123456789abcdef",
                "username": "homelab-iac",
            }
        )
    )
    handoff.chmod(0o600)
    result = subprocess.run(
        ["bash", str(RETIRE_BOOTSTRAP), "--check", str(handoff)],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "authentik retirement handoff OK"
    assert "never-print" not in result.stdout + result.stderr


def test_authentik_retirement_removes_bootstrap_material():
    source = RETIRE_BOOTSTRAP.read_text()
    assert "authentik-bootstrap-token" in source
    assert "Authorization: Bearer" in source
    assert "authentik_iac_token" in source
    assert "del(.authentik_bootstrap_token)" in source
    assert "del(.authentik_bootstrap_password_hash)" in source
    assert "delete secret authentik-bootstrap" in source
    assert 'rm -f -- "$handoff"' in source
    assert "authentik_breakglass_password" not in source


def test_authentik_retirement_has_a_documented_entrypoint():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("retire-authentik-bootstrap ", 1)[1].split(
        "\n\n", 1
    )[0]
    assert "scripts/retire-authentik-bootstrap.sh" in recipe


def test_harbor_iam_snapshot_is_unique_private_and_off_host():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("harbor-iam-snapshot:", 1)[1].split("\n# ", 1)[0]

    assert "pg_dumpall -U postgres" in recipe
    assert "just harbor-iam-preflight" in recipe
    assert 'date -u +%Y%m%dT%H%M%SZ' in recipe
    assert 'test ! -e "$target"' in recipe
    assert "install -d -m 0700" in recipe
    assert "chmod 0600" in recipe
    assert "{{ip_orion}}" in recipe
    assert "sha256sum" in recipe
    assert "set -x" not in recipe
