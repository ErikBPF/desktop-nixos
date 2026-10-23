#!/usr/bin/env python3
"""Repository config and credential selection for the PR review pipeline.

Owned repos use a GitHub App installation token (short-lived, fine-grained).
Upstream public repos use the dedicated bot account's classic token, because
GitHub fine-grained PATs cannot write there and an App cannot be installed
without admin.
"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

API = "https://api.github.com"


def load_config(path: str) -> list[dict]:
    data = json.loads(Path(path).read_text())
    repos = data.get("repos")
    if not isinstance(repos, list) or not repos:
        raise ValueError("config must contain a non-empty repos list")
    seen = set()
    for entry in repos:
        repo = entry.get("repo")
        if not isinstance(repo, str) or "/" not in repo:
            raise ValueError(f"invalid repo entry: {entry!r}")
        if repo in seen:
            raise ValueError(f"duplicate repo: {repo}")
        seen.add(repo)
        entry.setdefault("author", "ErikBPF")
        entry.setdefault("credential", "app")
        if entry["credential"] not in ("app", "upstream"):
            raise ValueError(f"{repo}: credential must be app or upstream")
        if not entry.get("bot_login"):
            raise ValueError(f"{repo}: bot_login is required")
    return repos


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _jwt(app_id: str, private_key: str) -> str:
    header = _b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    now = int(time.time())
    payload = _b64url(
        json.dumps({"iat": now - 60, "exp": now + 540, "iss": app_id}).encode()
    )
    signing_input = f"{header}.{payload}".encode()
    with tempfile.TemporaryDirectory() as tmp:
        key = Path(tmp) / "key.pem"
        key.write_text(private_key)
        key.chmod(0o600)
        data = Path(tmp) / "data"
        data.write_bytes(signing_input)
        sig = Path(tmp) / "sig"
        subprocess.run(
            [
                "openssl",
                "dgst",
                "-sha256",
                "-sign",
                str(key),
                "-out",
                str(sig),
                str(data),
            ],
            check=True,
            capture_output=True,
        )
        signature = _b64url(sig.read_bytes())
    return f"{header}.{payload}.{signature}"


def _app_token(credential_path: str, cache_path: str) -> str:
    cache = Path(cache_path)
    if cache.exists():
        try:
            cached = json.loads(cache.read_text())
            if cached.get("expires_at", 0) - 300 > time.time():
                return cached["token"]
        except (ValueError, KeyError, TypeError):
            pass
    cred = json.loads(Path(credential_path).read_text())
    jwt = _jwt(cred["app_id"], cred["private_key"])
    request = urllib.request.Request(
        f"{API}/app/installations/{cred['installation_id']}/access_tokens",
        method="POST",
        headers={
            "Authorization": f"Bearer {jwt}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = json.loads(response.read())
    except urllib.error.HTTPError as exc:
        raise RuntimeError(
            f"GitHub App token exchange failed ({exc.code}): {exc.read()[:300]!r}"
        ) from exc
    expires = datetime.fromisoformat(
        data["expires_at"].replace("Z", "+00:00")
    ).timestamp()
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(
        json.dumps({"token": data["token"], "expires_at": expires}, indent=2)
        + "\n"
    )
    cache.chmod(0o600)
    return data["token"]


def token_for(
    entry: dict, app_credential: str, app_token_cache: str
) -> str:
    if entry.get("credential") == "app":
        return _app_token(app_credential, app_token_cache)
    token = os.environ.get("GH_REVIEW_UPSTREAM_TOKEN", "")
    if not token:
        raise RuntimeError("GH_REVIEW_UPSTREAM_TOKEN is missing")
    return token


def gh_env(token: str) -> dict:
    env = os.environ.copy()
    env["GH_TOKEN"] = token
    env.pop("GITHUB_TOKEN", None)
    return env
