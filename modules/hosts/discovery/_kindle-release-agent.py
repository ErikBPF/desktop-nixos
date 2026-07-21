#!/usr/bin/env python3
import base64
import collections.abc
import dataclasses
import datetime
import errno
import fcntl
import http.client
import json
import os
import pathlib
import pwd
import re
import stat
import subprocess
import tempfile
import time
import types
import urllib.parse


SERVARR_BRANCH = "main"
SERVARR_REPO = pathlib.Path("/home/erik/servarr")
COMPOSE_PATH = "machines/discovery/kindle-dash.compose.yml"
GHCR_IMAGE = "ghcr.io/erikbpf/kindle-dash"
HARBOR_IMAGE = "harbor.homelab.pastelariadev.com/library/kindle-dash"
KINDLE_UNIT = "podman-compose-kindle-dash.service"
KINDLE_CONTAINER = "kindle-dash"
KINDLE_VOLUME = "discovery_kindle_dash_data"
KINDLE_URL = "http://kindle.homelab.pastelariadev.com/dash.png"
HARBOR_MIRROR_SCRIPT = (
    SERVARR_REPO / "machines/discovery/scripts/harbor-mirror.sh"
)
COSIGN_IDENTITY = (
    "https://github.com/ErikBPF/kindle-dash/"
    ".github/workflows/publish.yml@refs/heads/main"
)
COSIGN_ISSUER = "https://token.actions.githubusercontent.com"

STATE_PATH = pathlib.Path("/var/lib/kindle-release-agent/state.json")
METRIC_PATH = pathlib.Path(
    "/var/lib/node-exporter-textfile/kindle-release-agent.prom"
)
LOCK_PATH = pathlib.Path("/run/kindle-release-agent/lock")
HARBOR_ENV = pathlib.Path("/run/vault-agent/harbor.env")
GITHUB_APP_CONFIG = pathlib.Path(
    "/run/vault-agent/kindle-release-github-app.json"
)
GITHUB_APP_KEY = pathlib.Path(
    "/run/vault-agent/kindle-release-github-app.pem"
)
DISCORD_DEPLOYS_WEBHOOK = pathlib.Path(
    "/run/vault-agent/kindle-release-discord-deploys"
)
DISCORD_INCIDENTS_WEBHOOK = pathlib.Path(
    "/run/vault-agent/kindle-release-discord-incidents"
)
GITHUB_API_HOST = "api.github.com"
GITHUB_REPOSITORY_OWNER = "ErikBPF"
GITHUB_REPOSITORY = "servarr"
GITHUB_USER_AGENT = "kindle-release-agent/1"
FAIL_AFTER_RECREATE = False
DISCORD_HOST = "discord.com"
DEPLOY_USER = "erik"

PIN_RE = re.compile(
    rf"^\s*image:\s*{re.escape(HARBOR_IMAGE)}:"
    r"(v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))"
    r"@(sha256:[0-9a-f]{64})\s*$",
    re.MULTILINE,
)

FORWARD_PHASES = (
    "observed",
    "verified",
    "mirrored",
    "activated",
    "recreated",
    "validated",
    "succeeded",
)
ROLLBACK_PHASES = (
    "rollback-activated",
    "rollback-recreated",
    "rollback-validated",
    "failed",
)
ALL_PHASES = FORWARD_PHASES + ROLLBACK_PHASES
STATE_FIELDS = (
    "schema",
    "version",
    "digest",
    "commit",
    "phase",
    "previous",
    "failure",
    "degradation",
    "rollback",
    "updated_at",
)
STATE_KEYS = set(STATE_FIELDS)
VERSION_RE = re.compile(r"^v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)$")
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
TIMESTAMP_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")


@dataclasses.dataclass(frozen=True, eq=False)
class Snapshot(collections.abc.Mapping):
    schema: int
    version: str
    digest: str
    commit: str
    phase: str
    previous: object
    failure: object
    degradation: object
    rollback: object
    updated_at: str

    def __getitem__(self, key):
        if key not in STATE_KEYS:
            raise KeyError(key)
        return getattr(self, key)

    def __iter__(self):
        return iter(STATE_FIELDS)

    def __len__(self):
        return len(STATE_FIELDS)

    def __eq__(self, other):
        if not isinstance(other, collections.abc.Mapping):
            return NotImplemented
        return self.to_dict() == dict(other)

    def to_dict(self):
        state = {field: getattr(self, field) for field in STATE_FIELDS}
        if self.previous is not None:
            state["previous"] = dict(self.previous)
        return state


@dataclasses.dataclass(frozen=True)
class TerminalReport:
    snapshot: Snapshot

    def to_dict(self):
        return self.snapshot.to_dict()


class ExternalReportingError(RuntimeError):
    pass


class ExternalCredentialError(ExternalReportingError):
    pass


class ExternalSigningError(ExternalReportingError):
    pass


class ExternalHttpError(ExternalReportingError):
    pass


@dataclasses.dataclass(frozen=True)
class HttpRequest:
    method: str
    host: str
    endpoint: str = dataclasses.field(repr=False)
    headers: collections.abc.Mapping = dataclasses.field(repr=False)
    body: bytes = dataclasses.field(repr=False)

    def __repr__(self):
        endpoint = self.endpoint
        if self.host == DISCORD_HOST:
            endpoint = "/api/webhooks/<redacted>"
        return (
            f"HttpRequest(method={self.method!r}, host={self.host!r}, "
            f"endpoint={endpoint!r}, body=<redacted>)"
        )


@dataclasses.dataclass(frozen=True)
class HttpResponse:
    status: int
    headers: collections.abc.Mapping
    body: bytes


class FileSecretStore:
    def read(self, path):
        try:
            metadata = os.lstat(path)
            if (
                not stat.S_ISREG(metadata.st_mode)
                or metadata.st_uid != 0
                or stat.S_IMODE(metadata.st_mode) != 0o600
            ):
                raise ExternalCredentialError(
                    "external credential unavailable"
                )
            return pathlib.Path(path).read_text()
        except ExternalCredentialError:
            raise
        except Exception:
            raise ExternalCredentialError(
                "external credential unavailable"
            ) from None


class OpenSslJwtSigner:
    def sign(self, signing_input, pem):
        try:
            with tempfile.NamedTemporaryFile() as message:
                message.write(signing_input)
                message.flush()
                completed = subprocess.run(
                    [
                        "openssl",
                        "dgst",
                        "-sha256",
                        "-sign",
                        "/dev/stdin",
                        message.name,
                    ],
                    input=pem.encode(),
                    check=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )
            if not completed.stdout:
                raise ExternalSigningError(
                    "external signature unavailable"
                )
            return completed.stdout
        except ExternalSigningError:
            raise
        except Exception:
            raise ExternalSigningError(
                "external signature unavailable"
            ) from None


class HttpsClient:
    def send(self, request):
        if request.host not in {GITHUB_API_HOST, DISCORD_HOST}:
            raise ExternalHttpError("external HTTP request failed")
        connection = None
        try:
            connection = http.client.HTTPSConnection(request.host, timeout=10)
            connection.request(
                request.method,
                request.endpoint,
                body=request.body,
                headers=dict(request.headers),
            )
            response = connection.getresponse()
            body = response.read(1024 * 1024 + 1)
            if len(body) > 1024 * 1024:
                raise ExternalHttpError("external HTTP response invalid")
            return HttpResponse(response.status, dict(response.getheaders()), body)
        except ExternalReportingError:
            raise
        except Exception:
            raise ExternalHttpError("external HTTP request failed") from None
        finally:
            if connection is not None:
                connection.close()


def terminal_report(state):
    snapshot = validate_state(state)
    if snapshot.phase not in {"succeeded", "failed"}:
        raise ValueError("external report requires terminal snapshot")
    return TerminalReport(snapshot)


def _report_json(report):
    if not isinstance(report, TerminalReport):
        raise ValueError("invalid terminal report")
    validated = terminal_report(report.snapshot)
    return json.dumps(
        validated.to_dict(),
        sort_keys=True,
        separators=(",", ":"),
    )


def github_check_payload(report):
    normalized = _report_json(report)
    snapshot = report.snapshot
    if snapshot.phase == "failed":
        conclusion = "failure"
    elif snapshot.degradation is not None:
        conclusion = "neutral"
    else:
        conclusion = "success"
    return {
        "name": "kindle-release-agent",
        "head_sha": snapshot.commit,
        "status": "completed",
        "conclusion": conclusion,
        "completed_at": snapshot.updated_at,
        "output": {
            "title": f"Kindle release {snapshot.phase}",
            "summary": normalized,
        },
    }


def discord_payload(report):
    return {"content": _report_json(report)}


def _json_bytes(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def _base64url(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


class ExternalReporter:
    def __init__(self, http_client=None, signer=None, clock=None, secrets=None):
        self.http_client = http_client or HttpsClient()
        self.signer = signer or OpenSslJwtSigner()
        self.clock = clock or (lambda: int(datetime.datetime.now().timestamp()))
        self.secrets = secrets or FileSecretStore()

    def _read_secret(self, path):
        try:
            value = self.secrets.read(path)
            if not isinstance(value, str) or not value.strip():
                raise ValueError
            return value
        except ExternalCredentialError:
            raise
        except Exception:
            raise ExternalCredentialError(
                "external credential unavailable"
            ) from None

    def _github_config(self):
        try:
            config = json.loads(self._read_secret(GITHUB_APP_CONFIG))
            if (
                not isinstance(config, dict)
                or set(config) != {"app_id", "installation_id"}
                or type(config["app_id"]) is not int
                or type(config["installation_id"]) is not int
                or config["app_id"] <= 0
                or config["installation_id"] <= 0
            ):
                raise ValueError
            return config
        except ExternalCredentialError:
            raise
        except Exception:
            raise ExternalCredentialError(
                "external credential unavailable"
            ) from None

    def _app_jwt(self, app_id, pem):
        now = self.clock()
        if type(now) is not int or now <= 0:
            raise ExternalSigningError("external signature unavailable")
        header = _base64url(_json_bytes({"alg": "RS256", "typ": "JWT"}))
        claims = _base64url(
            _json_bytes({"iat": now - 60, "exp": now + 540, "iss": str(app_id)})
        )
        signing_input = f"{header}.{claims}".encode()
        try:
            signature = self.signer.sign(signing_input, pem)
            if not isinstance(signature, bytes) or not signature:
                raise ValueError
        except ExternalSigningError:
            raise
        except Exception:
            raise ExternalSigningError(
                "external signature unavailable"
            ) from None
        return f"{header}.{claims}.{_base64url(signature)}"

    def _send(self, request):
        try:
            response = self.http_client.send(request)
        except ExternalHttpError:
            raise
        except Exception:
            raise ExternalHttpError("external HTTP request failed") from None
        if (
            not isinstance(response, HttpResponse)
            or type(response.status) is not int
            or not 200 <= response.status < 300
        ):
            print(
                json.dumps(
                    {
                        "event": "external-http-invalid",
                        "endpoint": request.endpoint,
                        "status": getattr(response, "status", None),
                    },
                    separators=(",", ":"),
                )
            )
            raise ExternalHttpError("external HTTP response invalid")
        return response

    @staticmethod
    def _installation_token(response):
        try:
            payload = json.loads(response.body)
            if (
                not isinstance(payload, dict)
                or set(payload)
                != {
                    "token",
                    "expires_at",
                    "permissions",
                    "repository_selection",
                    "repositories",
                }
                or not isinstance(payload["token"], str)
                or not re.fullmatch(r"ghs_[A-Za-z0-9]{20,255}", payload["token"])
                or payload["permissions"]
                != {"checks": "write", "metadata": "read"}
                or payload["repository_selection"] != "selected"
                or not isinstance(payload["repositories"], list)
                or len(payload["repositories"]) != 1
                or not isinstance(payload["repositories"][0], dict)
                or payload["repositories"][0].get("name") != GITHUB_REPOSITORY
                or payload["repositories"][0].get("full_name")
                != f"{GITHUB_REPOSITORY_OWNER}/{GITHUB_REPOSITORY}"
                or not isinstance(payload["expires_at"], str)
            ):
                raise ValueError
            datetime.datetime.strptime(
                payload["expires_at"], "%Y-%m-%dT%H:%M:%SZ"
            )
            return payload["token"]
        except Exception:
            print('{"event":"external-token-invalid"}')
            raise ExternalHttpError(
                "external HTTP response invalid"
            ) from None

    def report_github(self, report):
        normalized = terminal_report(report.snapshot)
        config = self._github_config()
        pem = self._read_secret(GITHUB_APP_KEY)
        jwt = self._app_jwt(config["app_id"], pem)
        token_response = self._send(
            HttpRequest(
                "POST",
                GITHUB_API_HOST,
                f"/app/installations/{config['installation_id']}/access_tokens",
                {
                    "Accept": "application/vnd.github+json",
                    "Authorization": f"Bearer {jwt}",
                    "X-GitHub-Api-Version": "2022-11-28",
                    "Content-Type": "application/json",
                    "User-Agent": GITHUB_USER_AGENT,
                },
                _json_bytes(
                    {
                        "repositories": [GITHUB_REPOSITORY],
                        "permissions": {"checks": "write"},
                    }
                ),
            )
        )
        token = self._installation_token(token_response)
        self._send(
            HttpRequest(
                "POST",
                GITHUB_API_HOST,
                f"/repos/{GITHUB_REPOSITORY_OWNER}/{GITHUB_REPOSITORY}/check-runs",
                {
                    "Accept": "application/vnd.github+json",
                    "Authorization": f"Bearer {token}",
                    "X-GitHub-Api-Version": "2022-11-28",
                    "Content-Type": "application/json",
                    "User-Agent": GITHUB_USER_AGENT,
                },
                _json_bytes(github_check_payload(normalized)),
            )
        )

    @staticmethod
    def _discord_endpoint(webhook):
        try:
            parsed = urllib.parse.urlsplit(webhook.strip())
            if (
                parsed.scheme != "https"
                or parsed.hostname != DISCORD_HOST
                or parsed.netloc != DISCORD_HOST
                or parsed.query
                or parsed.fragment
                or not re.fullmatch(
                    r"/api/webhooks/[1-9][0-9]*/[A-Za-z0-9._-]{20,}",
                    parsed.path,
                )
            ):
                raise ValueError
            return parsed.path
        except Exception:
            raise ExternalCredentialError(
                "external credential unavailable"
            ) from None

    def report_discord(self, report):
        normalized = terminal_report(report.snapshot)
        snapshot = normalized.snapshot
        path = (
            DISCORD_DEPLOYS_WEBHOOK
            if snapshot.phase == "succeeded" and snapshot.degradation is None
            else DISCORD_INCIDENTS_WEBHOOK
        )
        endpoint = self._discord_endpoint(self._read_secret(path))
        self._send(
            HttpRequest(
                "POST",
                DISCORD_HOST,
                endpoint,
                {"Content-Type": "application/json"},
                _json_bytes(discord_payload(normalized)),
            )
        )

    def deliver(self, state):
        report = terminal_report(state)
        errors = []
        for provider, deliver in (
            ("github", self.report_github),
            ("discord", self.report_discord),
        ):
            try:
                deliver(report)
            except ExternalReportingError:
                errors.append(provider)
                print(
                    json.dumps(
                        {"event": "external-report-failed", "provider": provider},
                        separators=(",", ":"),
                    )
                )
        if errors:
            raise ExternalReportingError("external reporting unavailable")
        return report


class SubprocessRunner:
    def run(self, argv):
        return subprocess.run(
            argv,
            check=True,
            stdout=subprocess.PIPE,
            text=True,
        ).stdout

    def run_env(self, argv, environment):
        command_environment = os.environ.copy()
        command_environment.update(environment)
        return subprocess.run(
            argv,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=command_environment,
        ).stdout

    def run_bytes(self, argv):
        return subprocess.run(
            argv,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout


class SystemOperations:
    def __init__(self, runner, uid, harbor_env):
        self.runner = runner
        self.uid = uid
        self.harbor_env = pathlib.Path(harbor_env)

    @staticmethod
    def _candidate(state):
        return {
            "version": state["version"],
            "digest": state["digest"],
            "commit": state["commit"],
        }

    def execute(self, phase, state):
        candidate = self._candidate(state)
        if phase == "verified":
            verify_release(self.runner, candidate)
        elif phase == "mirrored":
            mirror_release(
                self.runner,
                candidate,
                load_harbor_robot(self.harbor_env),
            )
        elif phase == "activated":
            activate_revision(self.runner, state["commit"])
        elif phase == "recreated":
            recreate_kindle(self.runner, self.uid)
        elif phase == "validated":
            if FAIL_AFTER_RECREATE:
                raise RuntimeError("controlled post-recreate failure")
            validate_runtime(self.runner, state["digest"])
        elif phase == "rollback-activated":
            activate_revision(self.runner, state["previous"]["commit"])
        elif phase == "rollback-recreated":
            recreate_kindle(self.runner, self.uid)
        elif phase == "rollback-validated":
            validate_runtime(self.runner, state["previous"]["digest"])
        elif phase not in {"succeeded", "failed"}:
            raise ValueError(f"unsupported execution phase: {phase}")

    def revalidate(self, phase, state):
        candidate = self._candidate(state)
        if phase == "observed":
            if observe_candidate(self.runner, state["previous"]["commit"]) != candidate:
                raise ValueError("observed candidate drift")
        elif phase == "verified":
            verify_release(self.runner, candidate)
        elif phase == "mirrored":
            verify_release(self.runner, candidate)
            verify_harbor(self.runner, state["digest"])
        elif phase == "activated":
            verify_active_commit(self.runner, state["commit"])
        elif phase in {"recreated", "validated", "succeeded"}:
            verify_active_commit(self.runner, state["commit"])
            validate_runtime(self.runner, state["digest"])
        elif phase == "rollback-activated":
            verify_active_commit(self.runner, state["previous"]["commit"])
        elif phase in {"rollback-recreated", "rollback-validated", "failed"}:
            verify_active_commit(self.runner, state["previous"]["commit"])
            validate_runtime(self.runner, state["previous"]["digest"])
        else:
            raise ValueError(f"unsupported revalidation phase: {phase}")


def parse_pin(compose_text):
    matches = PIN_RE.findall(compose_text)
    if len(matches) != 1:
        raise ValueError(f"expected exactly one canonical Kindle pin, found {len(matches)}")
    return matches[0]


def validate_candidate(commit, changed_paths, compose_text):
    if not COMMIT_RE.fullmatch(commit):
        raise ValueError("invalid candidate commit")
    if changed_paths != [COMPOSE_PATH]:
        raise ValueError("candidate changes files outside the fixed Compose path")
    version, digest = parse_pin(compose_text)
    return {
        "commit": commit,
        "version": version,
        "digest": digest,
    }


def observe_candidate(runner, previous_commit):
    if not COMMIT_RE.fullmatch(previous_commit):
        raise ValueError("invalid previous commit")
    git = ["runuser", "-u", DEPLOY_USER, "--", "git", "-C", str(SERVARR_REPO)]
    runner.run(git + ["fetch", "--prune", "origin", SERVARR_BRANCH])
    commit = runner.run(
        git + ["rev-parse", f"refs/remotes/origin/{SERVARR_BRANCH}"]
    ).strip()
    if commit == previous_commit:
        return None
    runner.run(git + ["merge-base", "--is-ancestor", previous_commit, commit])
    changed_paths = runner.run(
        git + ["diff", "--name-only", f"{previous_commit}..{commit}"]
    ).splitlines()
    compose_text = runner.run(git + ["show", f"{commit}:{COMPOSE_PATH}"])
    return validate_candidate(commit, changed_paths, compose_text)


def observe_live_release(runner):
    git = [
        "runuser",
        "-u",
        DEPLOY_USER,
        "--",
        "git",
        "-C",
        str(SERVARR_REPO),
    ]
    runner.run(git + ["fetch", "origin", SERVARR_BRANCH])
    commit = runner.run(git + ["rev-parse", "HEAD"]).strip()
    if not COMMIT_RE.fullmatch(commit):
        raise ValueError("invalid active commit")
    runner.run(
        git
        + [
            "merge-base",
            "--is-ancestor",
            commit,
            f"refs/remotes/origin/{SERVARR_BRANCH}",
        ]
    )
    compose_text = runner.run(git + ["show", f"{commit}:{COMPOSE_PATH}"])
    version, digest = parse_pin(compose_text)
    return {
        "commit": commit,
        "version": version,
        "digest": digest,
    }


def verify_release(runner, candidate):
    validate_candidate(
        candidate["commit"],
        [COMPOSE_PATH],
        f"image: {HARBOR_IMAGE}:{candidate['version']}@{candidate['digest']}\n",
    )
    runner.run(
        [
            "cosign",
            "verify",
            "--certificate-identity",
            COSIGN_IDENTITY,
            "--certificate-oidc-issuer",
            COSIGN_ISSUER,
            f"{GHCR_IMAGE}@{candidate['digest']}",
        ]
    )
    tag_digest = runner.run(
        [
            "skopeo",
            "inspect",
            "--format",
            "{{.Digest}}",
            f"docker://{GHCR_IMAGE}:{candidate['version']}",
        ]
    ).strip()
    if tag_digest != candidate["digest"]:
        raise ValueError(
            f"tag digest mismatch: expected {candidate['digest']}, got {tag_digest}"
        )


def load_harbor_robot(path):
    required = {"HARBOR_ROBOT_USER", "HARBOR_ROBOT_SECRET"}
    values = {}
    for line in pathlib.Path(path).read_text().splitlines():
        key, separator, value = line.partition("=")
        if not separator or key not in required:
            continue
        if key in values:
            raise ValueError(f"duplicate Harbor robot key: {key}")
        values[key] = value
    if set(values) != required or not all(values.values()):
        raise ValueError("Harbor robot credentials are incomplete")
    return values


def mirror_release(runner, candidate, environment):
    if set(environment) != {"HARBOR_ROBOT_USER", "HARBOR_ROBOT_SECRET"}:
        raise ValueError("mirror environment must contain only robot credentials")
    validate_candidate(
        candidate["commit"],
        [COMPOSE_PATH],
        f"image: {HARBOR_IMAGE}:{candidate['version']}@{candidate['digest']}\n",
    )
    runner.run_env(
        [
            str(HARBOR_MIRROR_SCRIPT),
            candidate["version"],
            candidate["digest"],
        ],
        environment,
    )


def verify_harbor(runner, digest):
    if not DIGEST_RE.fullmatch(digest):
        raise ValueError("invalid Harbor digest")
    actual = runner.run(
        [
            "skopeo",
            "inspect",
            "--format",
            "{{.Digest}}",
            f"docker://{HARBOR_IMAGE}@{digest}",
        ]
    ).strip()
    if actual != digest:
        raise ValueError(f"Harbor digest mismatch: expected {digest}, got {actual}")


def activate_revision(runner, commit):
    if not COMMIT_RE.fullmatch(commit):
        raise ValueError("invalid activation commit")
    git = ["runuser", "-u", "erik", "--", "git", "-C", str(SERVARR_REPO)]
    runner.run(git + ["cat-file", "-e", f"{commit}^{{commit}}"])
    runner.run(
        git
        + [
            "merge-base",
            "--is-ancestor",
            commit,
            f"refs/remotes/origin/{SERVARR_BRANCH}",
        ]
    )
    runner.run(git + ["reset", "--hard", commit])


def verify_active_commit(runner, commit):
    if not COMMIT_RE.fullmatch(commit):
        raise ValueError("invalid active commit")
    actual = runner.run(
        [
            "runuser",
            "-u",
            "erik",
            "--",
            "git",
            "-C",
            str(SERVARR_REPO),
            "rev-parse",
            "HEAD",
        ]
    ).strip()
    if actual != commit:
        raise ValueError(f"active Servarr commit mismatch: expected {commit}, got {actual}")


def recreate_kindle(runner, uid):
    if not isinstance(uid, int) or uid <= 0:
        raise ValueError("invalid deploy user uid")
    runner.run(
        [
            "runuser",
            "-u",
            "erik",
            "--",
            "env",
            f"XDG_RUNTIME_DIR=/run/user/{uid}",
            "systemctl",
            "--user",
            "restart",
            KINDLE_UNIT,
        ]
    )


def validate_runtime(runner, digest):
    if not DIGEST_RE.fullmatch(digest):
        raise ValueError("invalid runtime digest")
    containers = json.loads(runner.run(["docker", "inspect", KINDLE_CONTAINER]))
    for _attempt in range(30):
        if (
            isinstance(containers, list)
            and len(containers) == 1
            and containers[0].get("State", {}).get("Health", {}).get("Status")
            == "starting"
        ):
            time.sleep(2)
            containers = json.loads(
                runner.run(["docker", "inspect", KINDLE_CONTAINER])
            )
            continue
        break
    if not isinstance(containers, list) or len(containers) != 1:
        raise ValueError("unexpected Kindle container inventory")
    container = containers[0]
    if container.get("State", {}).get("Health", {}).get("Status") != "healthy":
        raise ValueError("Kindle container is not healthy")
    if (
        container.get("Config", {})
        .get("Labels", {})
        .get("com.docker.compose.project")
        != "kindle-dash"
    ):
        raise ValueError("Kindle Compose owner differs")
    mounts = container.get("Mounts", [])
    if (
        len(
            [
                mount
                for mount in mounts
                if mount.get("Name") == KINDLE_VOLUME
                and mount.get("Destination") == "/data"
            ]
        )
        != 1
    ):
        raise ValueError("Kindle persistent volume differs")
    image_id = container.get("Image")
    images = json.loads(runner.run(["docker", "image", "inspect", image_id]))
    if not isinstance(images, list) or len(images) != 1:
        raise ValueError("unexpected Kindle image inventory")
    expected = f"{HARBOR_IMAGE}@{digest}"
    if expected not in images[0].get("RepoDigests", []):
        raise ValueError("running Kindle digest differs")
    png = runner.run_bytes(
        [
            "curl",
            "--fail",
            "--silent",
            "--show-error",
            "--resolve",
            "kindle.homelab.pastelariadev.com:80:192.168.10.210",
            KINDLE_URL,
        ]
    )
    if not png.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("Kindle dashboard is not a PNG")


def adopt_live_baseline(runner, persist, now):
    candidate = observe_live_release(runner)
    verify_release(runner, candidate)
    verify_harbor(runner, candidate["digest"])
    verify_active_commit(runner, candidate["commit"])
    validate_runtime(runner, candidate["digest"])
    state = validate_state(
        {
            "schema": 1,
            "version": candidate["version"],
            "digest": candidate["digest"],
            "commit": candidate["commit"],
            "phase": "succeeded",
            "previous": None,
            "failure": None,
            "degradation": None,
            "rollback": None,
            "updated_at": now(),
        }
    )
    persist(state)
    return state


def next_phase(current):
    try:
        index = FORWARD_PHASES.index(current)
    except ValueError as error:
        raise ValueError(f"unknown phase: {current}") from error
    if index + 1 == len(FORWARD_PHASES):
        raise ValueError("succeeded is terminal")
    return FORWARD_PHASES[index + 1]


def _plan(phases, current):
    try:
        index = phases.index(current)
    except ValueError as error:
        raise ValueError(f"phase does not belong to plan: {current}") from error
    return [("revalidate", current)] + [
        ("execute", phase) for phase in phases[index + 1 :]
    ]


def resume_plan(current):
    return _plan(FORWARD_PHASES, current)


def rollback_plan(current):
    return _plan(ROLLBACK_PHASES, current)


def _validate_pattern(value, pattern, message):
    if not isinstance(value, str) or not pattern.fullmatch(value):
        raise ValueError(message)


def _validate_optional_message(value, field):
    if value is not None and (
        not isinstance(value, str) or not value.strip() or len(value) > 4096
    ):
        raise ValueError(f"invalid state {field}")


def validate_state(state):
    if not isinstance(state, collections.abc.Mapping) or set(state) != STATE_KEYS:
        raise ValueError("state schema keys differ")
    if type(state["schema"]) is not int or state["schema"] != 1:
        raise ValueError("unsupported state schema")
    _validate_pattern(state["version"], VERSION_RE, "invalid state version")
    _validate_pattern(state["digest"], DIGEST_RE, "invalid state digest")
    _validate_pattern(state["commit"], COMMIT_RE, "invalid state commit")
    if not isinstance(state["phase"], str) or state["phase"] not in ALL_PHASES:
        raise ValueError("invalid state phase")
    _validate_pattern(state["updated_at"], TIMESTAMP_RE, "invalid state timestamp")
    try:
        datetime.datetime.strptime(state["updated_at"], "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as error:
        raise ValueError("invalid state timestamp") from error
    for field in ("failure", "degradation", "rollback"):
        _validate_optional_message(state[field], field)
    previous = state["previous"]
    if previous is not None:
        if not isinstance(previous, collections.abc.Mapping) or set(previous) != {
            "version",
            "digest",
            "commit",
        }:
            raise ValueError("invalid previous release")
        _validate_pattern(previous["version"], VERSION_RE, "invalid previous version")
        _validate_pattern(previous["digest"], DIGEST_RE, "invalid previous digest")
        _validate_pattern(previous["commit"], COMMIT_RE, "invalid previous commit")
        previous = types.MappingProxyType(dict(previous))
    if isinstance(state, Snapshot):
        return state
    return Snapshot(
        schema=state["schema"],
        version=state["version"],
        digest=state["digest"],
        commit=state["commit"],
        phase=state["phase"],
        previous=previous,
        failure=state["failure"],
        degradation=state["degradation"],
        rollback=state["rollback"],
        updated_at=state["updated_at"],
    )


def render_journal_event(state):
    snapshot = validate_state(state)
    event = {"event": "kindle-release-agent-snapshot"}
    event.update(snapshot.to_dict())
    return json.dumps(event, sort_keys=True, separators=(",", ":"))


def _prometheus_escape(value):
    if value is None:
        return ""
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


def render_prometheus(state):
    snapshot = validate_state(state)
    labels = {
        "version": snapshot.version,
        "digest": snapshot.digest,
        "commit": snapshot.commit,
        "phase": snapshot.phase,
        "failure": snapshot.failure,
        "degradation": snapshot.degradation,
        "rollback": snapshot.rollback,
    }
    rendered_labels = ",".join(
        f'{key}="{_prometheus_escape(value)}"' for key, value in labels.items()
    )
    updated = datetime.datetime.strptime(
        snapshot.updated_at,
        "%Y-%m-%dT%H:%M:%SZ",
    ).replace(tzinfo=datetime.timezone.utc)
    return (
        "# HELP kindle_release_agent_snapshot_info Current validated release snapshot.\n"
        "# TYPE kindle_release_agent_snapshot_info gauge\n"
        f"kindle_release_agent_snapshot_info{{{rendered_labels}}} 1\n"
        "# HELP kindle_release_agent_snapshot_updated_seconds Unix time of the snapshot update.\n"
        "# TYPE kindle_release_agent_snapshot_updated_seconds gauge\n"
        f"kindle_release_agent_snapshot_updated_seconds {int(updated.timestamp())}\n"
    )


def load_state(path):
    path = pathlib.Path(path)
    state = json.loads(path.read_text())
    return validate_state(state)


def _write_payload(stream, payload):
    stream.write(payload)


def _write_atomic(path, payload, file_mode, directory_mode):
    path = pathlib.Path(path)
    path.parent.mkdir(mode=directory_mode, parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.tmp-",
    )
    try:
        os.fchmod(descriptor, file_mode)
        stream = os.fdopen(descriptor, "wb")
        descriptor = None
        with stream:
            _write_payload(stream, payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if os.path.exists(temporary):
            os.unlink(temporary)


def write_state(path, state):
    snapshot = validate_state(state)
    payload = (
        json.dumps(snapshot.to_dict(), sort_keys=True, separators=(",", ":")) + "\n"
    ).encode()
    _write_atomic(path, payload, file_mode=0o600, directory_mode=0o700)


def write_metric(path, state):
    snapshot = validate_state(state)
    _write_atomic(
        path,
        render_prometheus(snapshot).encode(),
        file_mode=0o644,
        directory_mode=0o755,
    )


def persist_snapshot(state_path, metric_path, state):
    snapshot = validate_state(state)
    write_state(state_path, snapshot)
    print(render_journal_event(snapshot), flush=True)
    write_metric(metric_path, snapshot)
    return snapshot


def reconcile_metric(path, state):
    snapshot = validate_state(state)
    expected = render_prometheus(snapshot).encode()
    path = pathlib.Path(path)
    try:
        current = path.read_bytes()
    except FileNotFoundError:
        current = None
    if current == expected:
        return False
    write_metric(path, snapshot)
    return True


def transition(state, phase, updated_at):
    validate_state(state)
    chain = ROLLBACK_PHASES if state["phase"] in ROLLBACK_PHASES else FORWARD_PHASES
    try:
        expected = chain[chain.index(state["phase"]) + 1]
    except (ValueError, IndexError) as error:
        raise ValueError(f"terminal or unknown phase: {state['phase']}") from error
    if expected != phase:
        raise ValueError(f"illegal phase transition: {state['phase']} -> {phase}")
    advanced = dict(state)
    advanced["phase"] = phase
    advanced["updated_at"] = updated_at
    return validate_state(advanced)


def begin_rollback(state, reason, updated_at):
    validate_state(state)
    if state["phase"] not in {"activated", "recreated", "validated", "succeeded"}:
        raise ValueError(f"rollback is not allowed from phase: {state['phase']}")
    if not isinstance(reason, str) or not reason.strip():
        raise ValueError("rollback reason is required")
    rollback = dict(state)
    rollback["phase"] = "rollback-activated"
    rollback["failure"] = reason
    rollback["updated_at"] = updated_at
    return validate_state(rollback)


def run_rollback(state, reason, operations, persist, now):
    current = validate_state(state)
    try:
        operations.execute("rollback-activated", current)
        current = begin_rollback(current, reason, now())
        persist(current)
        for _, phase in rollback_plan(current["phase"])[1:]:
            operations.execute(phase, current)
            current = transition(current, phase, now())
            if phase == "failed":
                completed = current.to_dict()
                completed["rollback"] = "succeeded"
                current = validate_state(completed)
            persist(current)
        return current
    except Exception:
        failed = current.to_dict()
        failed["phase"] = "failed"
        failed["failure"] = reason
        failed["rollback"] = "failed"
        failed["updated_at"] = now()
        current = validate_state(failed)
        persist(current)
        return current


def resume_execution(state, operations, persist, now, after_revalidate=None):
    current = validate_state(state)
    if current.phase in FORWARD_PHASES:
        return run_forward(
            current,
            operations,
            persist,
            now,
            after_revalidate=after_revalidate,
        )
    if current.phase == "failed" and current.rollback == "failed":
        return current
    try:
        plan = rollback_plan(current.phase)
        for action, phase in plan:
            if action == "revalidate":
                operations.revalidate(phase, current)
                if after_revalidate is not None:
                    after_revalidate(current)
                continue
            operations.execute(phase, current)
            current = transition(current, phase, now())
            if phase == "failed":
                completed = current.to_dict()
                completed["rollback"] = "succeeded"
                current = validate_state(completed)
            persist(current)
        return current
    except Exception:
        failed = current.to_dict()
        failed["phase"] = "failed"
        failed["rollback"] = "failed"
        failed["updated_at"] = now()
        current = validate_state(failed)
        persist(current)
        return current


def run_forward(state, operations, persist, now, after_revalidate=None):
    current = validate_state(state)
    for action, phase in resume_plan(current["phase"]):
        try:
            if action == "revalidate":
                operations.revalidate(phase, current)
            else:
                operations.execute(phase, current)
        except Exception as error:
            if current["phase"] in {
                "activated",
                "recreated",
                "validated",
                "succeeded",
            }:
                return run_rollback(current, str(error), operations, persist, now)
            raise
        if action == "revalidate":
            if after_revalidate is not None:
                after_revalidate(current)
            continue
        current = transition(current, phase, now())
        persist(current)
    return current


def _utc_now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def report_terminal(result, reporter, persist, now):
    snapshot = result if isinstance(result, Snapshot) else validate_state(result)
    if snapshot.phase not in {"succeeded", "failed"}:
        raise ValueError("external report requires terminal snapshot")
    recovering = snapshot.degradation == "external-reporting-unavailable"
    if recovering:
        recovered = snapshot.to_dict()
        recovered["degradation"] = None
        recovered["updated_at"] = now()
        report_snapshot = validate_state(recovered)
    else:
        report_snapshot = snapshot
    try:
        reporter.deliver(report_snapshot)
    except ExternalReportingError:
        degraded = snapshot.to_dict()
        degraded["degradation"] = "external-reporting-unavailable"
        degraded["updated_at"] = now()
        snapshot = validate_state(degraded)
        persist(snapshot)
    else:
        if recovering:
            snapshot = report_snapshot
            persist(snapshot)
    return snapshot


def poll_release(state, operations, persist, now, after_revalidate):
    current = validate_state(state)
    operations.revalidate("succeeded", current)
    after_revalidate(current)
    candidate = observe_candidate(operations.runner, current["commit"])
    if candidate is None:
        return current
    observed = validate_state(
        {
            "schema": 1,
            **candidate,
            "phase": "observed",
            "previous": {
                "version": current["version"],
                "digest": current["digest"],
                "commit": current["commit"],
            },
            "failure": None,
            "degradation": None,
            "rollback": None,
            "updated_at": now(),
        }
    )
    persist(observed)
    return run_forward(
        observed,
        operations,
        persist,
        now,
        after_revalidate=after_revalidate,
    )


def recover_failed_attempt(state, operations, persist, now, after_revalidate):
    failed = validate_state(state)
    operations.revalidate("failed", failed)
    recovered_failure = failed.to_dict()
    recovered_failure["rollback"] = "succeeded"
    recovered_failure["updated_at"] = now()
    persist(validate_state(recovered_failure))
    previous = failed["previous"]
    recovered = validate_state(
        {
            "schema": 1,
            **dict(previous),
            "phase": "succeeded",
            "previous": None,
            "failure": None,
            "degradation": None,
            "rollback": None,
            "updated_at": now(),
        }
    )
    persist(recovered)
    return recovered


def execute_once():
    runner = SubprocessRunner()
    persist = lambda updated: persist_snapshot(STATE_PATH, METRIC_PATH, updated)
    try:
        state = load_state(STATE_PATH)
    except FileNotFoundError:
        result = adopt_live_baseline(runner, persist, _utc_now)
    else:
        uid = pwd.getpwnam(DEPLOY_USER).pw_uid
        operations = SystemOperations(runner, uid, HARBOR_ENV)
        reconcile = lambda snapshot: reconcile_metric(METRIC_PATH, snapshot)
        if state["phase"] == "succeeded":
            result = poll_release(state, operations, persist, _utc_now, reconcile)
        elif state["phase"] == "failed":
            result = recover_failed_attempt(
                state, operations, persist, _utc_now, reconcile
            )
        else:
            runner_function = (
                run_forward if state["phase"] in FORWARD_PHASES else resume_execution
            )
            result = runner_function(
                state,
                operations,
                persist,
                _utc_now,
                after_revalidate=reconcile,
            )
    result = report_terminal(result, ExternalReporter(), persist, _utc_now)
    return 1 if result["phase"] == "failed" else 0


def _acquire_lock():
    descriptor = os.open(LOCK_PATH, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as error:
        os.close(descriptor)
        if error.errno in {errno.EACCES, errno.EAGAIN}:
            return None
        raise
    return descriptor


def main():
    descriptor = _acquire_lock()
    if descriptor is None:
        print(json.dumps({"event": "lock-busy"}, separators=(",", ":")))
        return 0
    try:
        return execute_once()
    finally:
        os.close(descriptor)


if __name__ == "__main__":
    raise SystemExit(main())
