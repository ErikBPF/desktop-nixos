import base64
import hashlib
import json
import os
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
ADMIN_TOKEN = ROOT / "scripts/authentik-admin-token.sh"
ADMIN_TOKEN_MODEL = ROOT / "scripts/authentik-admin-token.py"
IAC_TOKEN_ROTATE = ROOT / "scripts/rotate-authentik-iac-token.sh"
PROVIDER_HANDOFF = ROOT / "scripts/harbor-iam-provider-handoff.sh"


class HarborHandler(BaseHTTPRequestHandler):
    users: ClassVar[list[dict]] = []
    user_details: ClassVar[dict[int, dict]] = {}

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
        if path.startswith("/api/v2.0/users/"):
            payload = self.user_details.get(int(path.rsplit("/", 1)[1]))
            if payload is None:
                self.send_response(404)
                self.end_headers()
                return
        else:
            payload = payloads[path]
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


def run_preflight(tmp_path, users, user_details=None):
    HarborHandler.users = users
    HarborHandler.user_details = user_details or {
        user["user_id"]: user for user in users
    }
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


def test_preflight_treats_missing_oidc_detail_as_local_without_writing_raw_detail(
    tmp_path,
):
    users = [
        {"user_id": 1, "username": "admin", "sysadmin_flag": True},
        {"user_id": 2, "username": "local-user", "sysadmin_flag": False},
    ]
    result = run_preflight(tmp_path, users, {1: users[0]})

    assert result.returncode == 2, result.stderr
    assert json.loads(result.stdout)["local_non_admin_users"] == ["local-user"]
    source = SCRIPT.read_text()
    assert '"$tmp/user-$user_id.json"' not in source


def test_preflight_uses_user_detail_to_identify_oidc_users(tmp_path):
    users = [
        {"user_id": 1, "username": "admin", "sysadmin_flag": True},
        {"user_id": 2, "username": "erik", "sysadmin_flag": False},
    ]
    result = run_preflight(
        tmp_path,
        users,
        {
            1: users[0],
            2: {
                **users[1],
                "oidc_user_meta": {
                    "subiss": "subject-issuer",
                    "secret": "must-not-appear",
                },
            },
        },
    )

    assert result.returncode == 0, result.stderr
    assert "must-not-appear" not in result.stdout
    evidence = json.loads(result.stdout)
    assert evidence["local_non_admin_users"] == []
    assert evidence["users"][1]["oidc"] is True


def test_recipe_runs_the_redacting_wrapper_on_discovery():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split('harbor-iam-preflight source="vault":', 1)[1].split(
        "\n# ", 1
    )[0]
    assert "scripts/harbor-iam-preflight.sh" in recipe
    assert "sudo /run/current-system/sw/bin/bash -s --" in recipe
    assert "/run/vault-agent/harbor.env" in recipe
    assert "/home/erik/servarr/machines/discovery/.env" in recipe
    assert "vault|fallback" in recipe


def test_harbor_diagnostic_is_read_only_and_value_free():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("harbor-iam-diagnostic:", 1)[1].split("\n# ", 1)[0]

    assert "systemctl status harbor.service" in recipe
    assert "journalctl -u harbor.service" in recipe
    assert "docker ps -a --format json" in recipe
    assert ".harbor-installer/current" in recipe
    assert "docker logs" not in recipe
    assert "harbor.env" not in recipe


def test_harbor_admin_credential_diagnostic_is_read_only_and_value_free():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("harbor-admin-credential-diagnostic:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "json_build_object" in recipe
    assert "length(salt)" in recipe
    assert "length(password)" in recipe
    assert "password_version" in recipe
    assert "harbor.env" not in recipe
    assert "docker logs" not in recipe
    assert not any(word in recipe.upper() for word in ("UPDATE ", "DELETE ", "INSERT "))


def test_harbor_admin_recovery_is_snapshot_and_confirmation_gated():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split(
        'harbor-admin-password-recover snapshot_id confirmation="":', 1
    )[1].split("\n# ", 1)[0]

    assert 'confirmation == "reset-db-admin-password"' in recipe
    assert "{{ip_orion}}" in recipe
    assert "sha256sum --check --status SHA256SUMS" in recipe
    assert "UPDATE harbor_user SET salt = '', password = ''" in recipe
    assert "user_id = 1 AND username = 'admin'" in recipe
    assert 'test "$updated" = 1' in recipe
    assert "docker restart harbor-core" in recipe
    assert "just harbor-iam-preflight vault" in recipe
    assert "pbkdf2_sha256" in recipe


def test_authentik_admin_token_is_short_lived_and_handoff_only(tmp_path):
    source = ADMIN_TOKEN_MODEL.read_text()
    helper = ADMIN_TOKEN.read_text()

    assert "timedelta(minutes=15)" in source
    assert 'username="akadmin"' in source
    assert 'identifier="bootstrap-homelab-iac-authentik-config-manager"' in source
    assert "AUTHENTIK_ADMIN_TOKEN=" in source
    assert "kubectl --context homelab" in helper
    assert "deployment/authentik-worker" in helper
    assert "install -m 0600" in helper
    assert 'rm -f -- "$handoff"' in helper
    assert 'echo "$token"' not in helper


def test_authentik_admin_token_handoff_never_prints_token(tmp_path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    fake_kubectl = fake_bin / "kubectl"
    fake_kubectl.write_text(
        "#!/usr/bin/env bash\n"
        "cat >/dev/null\n"
        "if [[ $* == *AUTHENTIK_TOKEN_ACTION=create* ]]; then\n"
        '  echo \'AUTHENTIK_ADMIN_TOKEN={"token":"never-print-token-0123456789abcdef"}\'\n'
        "else\n"
        "  echo 'AUTHENTIK_ADMIN_TOKEN={\"revoked\":true}'\n"
        "fi\n"
    )
    fake_kubectl.chmod(0o755)
    handoff = tmp_path / "authentik-admin-token.secrets.json"
    env = os.environ | {"PATH": f"{fake_bin}:{os.environ['PATH']}"}

    created = subprocess.run(
        ["bash", str(ADMIN_TOKEN), "create", str(handoff)],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert created.returncode == 0, created.stderr
    assert "never-print" not in created.stdout + created.stderr
    assert oct(handoff.stat().st_mode & 0o777) == "0o600"
    assert json.loads(handoff.read_text())["token"].startswith("never-print-token")

    revoked = subprocess.run(
        ["bash", str(ADMIN_TOKEN), "revoke", str(handoff)],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert revoked.returncode == 0, revoked.stderr
    assert "never-print" not in revoked.stdout + revoked.stderr
    assert not handoff.exists()


def test_authentik_iac_token_rotation_is_service_scoped_and_direct_to_sops():
    model = ADMIN_TOKEN_MODEL.read_text()
    helper = IAC_TOKEN_ROTATE.read_text()

    assert 'action == "rotate-iac"' in model
    assert 'username="svc-homelab-iac-authentik-config-manager"' in model
    assert 'identifier="svc-homelab-iac-authentik-config-manager-api-token"' in model
    assert "default_token_key()" in model
    assert '"expiring": True' in model
    assert '"expires": now() + timedelta(days=90)' in model
    assert 'service_account.type not in ("service_account", "internal_service_account")' in model
    assert "service_account.is_superuser" in model
    assert "kubectl --context homelab" in helper
    assert "AUTHENTIK_TOKEN_ACTION=rotate-iac" in helper
    assert "sops --decrypt" in helper
    assert "sops --encrypt" in helper
    assert ".authentik_iac_token = load_str" in helper
    assert 'install -m 0600 "$tmp/encrypted.yaml" "$sops_file"' in helper
    assert 'echo "$token"' not in helper


def test_harbor_project_iam_approle_credentials_are_rotated_directly_to_sops():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("capture-harbor-project-iam-approle-secrets:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "reader publisher" in recipe
    assert "svc-homelab-iac-openbao-harbor-project-iam-$capability" in recipe
    assert "--request LIST" in recipe
    assert '--write-out "%{http_code}"' in recipe
    assert "404) accessors=" in recipe
    assert "secret-id-accessor/destroy" in recipe
    assert "openbao_harbor_project_iam_$capability" in recipe
    assert recipe.count("sops set --value-stdin") == 2
    assert recipe.count("jq -jer") == 2
    assert 'echo "$credentials"' not in recipe


def test_authentik_iac_token_rotation_has_a_documented_entrypoint():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("rotate-authentik-iac-token:", 1)[1].split("\n\n", 1)[0]
    assert "scripts/rotate-authentik-iac-token.sh" in recipe


def test_harbor_provider_handoff_is_private_ignored_and_value_free(tmp_path):
    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    (repo / ".gitignore").write_text("*.secrets.json\n")
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    (fake_bin / "sops").write_text(
        "#!/usr/bin/env bash\nprintf '%s\\n' 'never-print-token-0123456789abcdef'\n"
    )
    (fake_bin / "ssh").write_text(
        "#!/usr/bin/env bash\nprintf '%s\\n' 'never-print-password-0123456789abcdef'\n"
    )
    for command in (fake_bin / "sops", fake_bin / "ssh"):
        command.chmod(0o755)
    sops_file = tmp_path / "secrets.yaml"
    sops_file.touch()
    handoff = repo / "harbor-iam-bootstrap-provider.secrets.json"
    env = os.environ | {
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "AUTHENTIK_SOPS_FILE": str(sops_file),
    }

    created = subprocess.run(
        ["bash", str(PROVIDER_HANDOFF), "create", str(handoff), "192.0.2.1"],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert created.returncode == 0, created.stderr
    assert "never-print" not in created.stdout + created.stderr
    assert oct(handoff.stat().st_mode & 0o777) == "0o600"
    assert json.loads(handoff.read_text()) == {
        "authentik_config_manager_token": "never-print-token-0123456789abcdef",
        "harbor_bootstrap_admin_password": "never-print-password-0123456789abcdef",
    }

    deleted = subprocess.run(
        ["bash", str(PROVIDER_HANDOFF), "delete", str(handoff)],
        text=True,
        capture_output=True,
        check=False,
    )
    assert deleted.returncode == 0, deleted.stderr
    assert not handoff.exists()


def test_harbor_provider_handoff_rejects_unignored_destination(tmp_path):
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    handoff = tmp_path / "harbor-iam-bootstrap-provider.secrets.json"
    result = subprocess.run(
        ["bash", str(PROVIDER_HANDOFF), "create", str(handoff), "192.0.2.1"],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode != 0
    assert "ignored" in result.stderr
    assert not handoff.exists()


def test_harbor_provider_handoff_has_a_documented_entrypoint():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("harbor-iam-bootstrap-provider-handoff ", 1)[1].split(
        "\n\n", 1
    )[0]
    assert "scripts/harbor-iam-provider-handoff.sh" in recipe
    assert "{{ip_discovery}}" in recipe


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
                "username": "svc-homelab-iac-authentik-config-manager",
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
    recipe = justfile.split("retire-authentik-bootstrap ", 1)[1].split("\n\n", 1)[0]
    assert "scripts/retire-authentik-bootstrap.sh" in recipe


def test_harbor_iam_snapshot_is_unique_private_and_off_host():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("harbor-iam-snapshot:", 1)[1].split("\n# ", 1)[0]

    assert "pg_dumpall -U postgres" in recipe
    assert "just harbor-iam-preflight" in recipe
    assert "date -u +%Y%m%dT%H%M%SZ" in recipe
    assert 'test ! -e "$target"' in recipe
    assert "install -d -m 0700" in recipe
    assert "chmod 0600" in recipe
    assert "{{ip_orion}}" in recipe
    assert "sha256sum" in recipe
    assert "set -x" not in recipe
