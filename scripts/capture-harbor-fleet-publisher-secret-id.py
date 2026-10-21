#!/usr/bin/env python3
"""Refresh only the existing Harbor fleet-publisher bootstrap SecretID."""

import fcntl
import json
import os
import ssl
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

import yaml

ROLE = "svc-homelab-iac-openbao-harbor-fleet-readers-publisher"
URL = "https://openbao.homelab.pastelariadev.com/v1/auth/approle/role/" + ROLE
ROLE_KEY = '["homelab_iac"]["openbao_harbor_fleet_readers_publisher_role_id"]'
SECRET_KEY = '["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"]'
STORE = Path(__file__).resolve().parents[1] / "secrets/sops/secrets.yaml"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, url):
        raise ValueError("Credential-bearing redirects are forbidden")


def sops(*arguments, payload=None):
    result = subprocess.run(
        ["sops", *arguments], input=payload, capture_output=True, timeout=30, check=False
    )
    if result.returncode:
        raise ValueError("Sops operation failed")
    return result.stdout


def literal(value):
    if (
        not isinstance(value, str)
        or not 0 < len(value) <= 4096
        or value != value.strip()
        or "\n" in value
        or "\r" in value
    ):
        raise ValueError("Invalid credential literal")
    return value


def extract(key, store=STORE):
    return literal(sops("--decrypt", "--extract", key, str(store)).decode("utf-8"))


def main():
    if sys.argv[1:] != ["--exclusive-secret-store"]:
        print("Requires --exclusive-secret-store after an approved single-writer window; no other arguments accepted", file=sys.stderr)
        return 64
    os.umask(0o077)
    staged = None
    lock_fd = None
    issuance_attempted = False
    try:
        if not STORE.is_file() or STORE.is_symlink():
            raise ValueError("Sops store missing or symlinked")
        # All writers must honor this stable side lock; never unlink its inode.
        lock_fd = os.open(STORE.with_name(".secrets.yaml.harbor-publisher.lock"),
                          os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        os.fchmod(lock_fd, 0o600)
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if b"--value-stdin" not in sops("set", "--help"):
            raise ValueError("Sops stdin capture unsupported")
        original = STORE.read_bytes()  # Encrypted bytes only.
        # Sops emits raw scalars even with JSON output, erasing scalar types.
        # Owner-declared type only: Sops MAC does not authenticate this marker.
        target = yaml.safe_load(original)["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"]
        if not isinstance(target, str) or not target.startswith("ENC[AES256_GCM,") or not target.endswith(",type:str]"):
            raise ValueError("Existing SecretID must be an encrypted string")
        extract(SECRET_KEY)
        root = extract('["vault_root_token"]')
        role_id = extract(ROLE_KEY)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.load_default_certs()
        opener = urllib.request.build_opener(
            urllib.request.HTTPSHandler(context=context), NoRedirect(),
            urllib.request.ProxyHandler({}),
        )

        def request(path, payload=None):
            data = json.dumps(payload).encode() if payload is not None else None
            req = urllib.request.Request(
                URL + path,
                data=data,
                headers={"X-Vault-Token": root, "Content-Type": "application/json"},
            )
            try:
                with opener.open(req, timeout=20) as response:
                    return json.loads(response.read())
            except urllib.error.HTTPError as error:
                error.close()
                raise ValueError("Vault request failed") from None

        if literal(request("/role-id")["data"]["role_id"]) != role_id:
            raise ValueError("Stored RoleID does not match exact controller")
        fd, name = tempfile.mkstemp(
            prefix=".harbor-fleet-publisher-", suffix=".yaml", dir=STORE.parent
        )
        os.close(fd)
        staged = Path(name)
        staged.write_bytes(original)
        issuance_attempted = True
        secret_id = literal(request("/secret-id", {})["data"]["secret_id"])
        sops(
            "set", "--value-stdin", str(staged), SECRET_KEY,
            payload=json.dumps(secret_id).encode(),
        )
        if extract(SECRET_KEY, staged) != secret_id or STORE.read_bytes() != original:
            raise ValueError("Capture verification failed or store changed concurrently")
        staged.chmod(0o600)
        os.replace(staged, STORE)
        print("Harbor fleet-publisher SecretID captured into encrypted Sops; RoleID and readers unchanged")
        return 0
    except (Exception, KeyboardInterrupt):  # noqa: BLE001 - Never expose credential-bearing exception text.
        if issuance_attempted:
            print("STOP: SecretID issuance may have occurred; capture incomplete; do not rerun", file=sys.stderr)
        else:
            print("STOP: controller bootstrap preflight failed; no SecretID issuance attempted", file=sys.stderr)
        return 1
    finally:
        if staged is not None:
            staged.unlink(missing_ok=True)
        if lock_fd is not None:
            os.close(lock_fd)


if __name__ == "__main__":
    sys.exit(main())
