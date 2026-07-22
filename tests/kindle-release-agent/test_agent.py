import contextlib
import dataclasses
import datetime
import errno
import fcntl
import importlib.util
import inspect
import io
import json
import os
import pathlib
import stat
import subprocess
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
AGENT_PATH = ROOT / "modules/hosts/discovery/_kindle-release-agent.py"
MODULE_PATH = ROOT / "modules/hosts/discovery/kindle-release-agent.nix"
JUSTFILE_PATH = ROOT / "justfile"


def load_agent():
    spec = importlib.util.spec_from_file_location("kindle_release_agent", AGENT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PinContract(unittest.TestCase):
    def setUp(self):
        self.agent = load_agent()
        self.digest = "sha256:" + "a" * 64
        self.pin = (
            "harbor.homelab.pastelariadev.com/library/"
            f"kindle-dash:v1.2.3@{self.digest}"
        )

    def test_accepts_exactly_one_canonical_pin(self):
        version, digest = self.agent.parse_pin(f"    image: {self.pin}\n")
        self.assertEqual((version, digest), ("v1.2.3", self.digest))

    def test_rejects_missing_or_duplicate_pin(self):
        for text in ("services: {}\n", f"image: {self.pin}\nimage: {self.pin}\n"):
            with self.subTest(text=text):
                with self.assertRaises(ValueError):
                    self.agent.parse_pin(text)

    def test_authority_constants_are_fixed(self):
        self.assertEqual(self.agent.SERVARR_BRANCH, "main")
        self.assertEqual(
            self.agent.COMPOSE_PATH,
            "machines/discovery/kindle-dash.compose.yml",
        )
        self.assertEqual(
            self.agent.HARBOR_IMAGE,
            "harbor.homelab.pastelariadev.com/library/kindle-dash",
        )
        self.assertEqual(
            self.agent.KINDLE_UNIT,
            "podman-compose-kindle-dash.service",
        )

    def test_candidate_allows_only_the_fixed_compose_path(self):
        candidate = self.agent.validate_candidate(
            "b" * 40,
            [self.agent.COMPOSE_PATH],
            f"    image: {self.pin}\n",
        )
        self.assertEqual(
            candidate,
            {
                "commit": "b" * 40,
                "version": "v1.2.3",
                "digest": self.digest,
            },
        )
        for paths in (
            [],
            [self.agent.COMPOSE_PATH, "machines/discovery/other.yml"],
            ["machines/discovery/other.yml"],
        ):
            with self.subTest(paths=paths):
                with self.assertRaises(ValueError):
                    self.agent.validate_candidate(
                        "b" * 40,
                        paths,
                        f"    image: {self.pin}\n",
                    )

    def test_candidate_rejects_malformed_commit(self):
        with self.assertRaises(ValueError):
            self.agent.validate_candidate(
                "main",
                [self.agent.COMPOSE_PATH],
                f"    image: {self.pin}\n",
            )

    def test_active_revision_allows_unrelated_repository_advances(self):
        runner = mock.Mock()
        runner.run.side_effect = ["expected-blob\n", "expected-blob\n"]
        commit = "b" * 40
        self.agent.verify_active_commit(runner, commit)
        commands = runner.run.call_args_list
        self.assertEqual(len(commands), 2)
        self.assertIn(f"{commit}:{self.agent.COMPOSE_PATH}", commands[0].args[0])
        self.assertIn("hash-object", commands[1].args[0])
        self.assertNotIn("HEAD", commands[0].args[0] + commands[1].args[0])

    def test_active_revision_rejects_compose_drift(self):
        runner = mock.Mock()
        runner.run.side_effect = ["expected-blob\n", "different-blob\n"]
        with self.assertRaisesRegex(ValueError, "active Kindle compose mismatch"):
            self.agent.verify_active_commit(runner, "b" * 40)


class PhaseContract(unittest.TestCase):
    def setUp(self):
        self.agent = load_agent()

    def test_forward_phases_are_strict(self):
        phases = [
            "observed",
            "verified",
            "mirrored",
            "activated",
            "recreated",
            "validated",
            "succeeded",
        ]
        for current, expected in zip(phases, phases[1:]):
            self.assertEqual(self.agent.next_phase(current), expected)
        with self.assertRaises(ValueError):
            self.agent.next_phase("succeeded")
        with self.assertRaises(ValueError):
            self.agent.next_phase("unknown")

    def test_resume_revalidates_current_phase_before_remaining_work(self):
        self.assertEqual(
            self.agent.resume_plan("mirrored"),
            [
                ("revalidate", "mirrored"),
                ("execute", "activated"),
                ("execute", "recreated"),
                ("execute", "validated"),
                ("execute", "succeeded"),
            ],
        )
        self.assertEqual(
            self.agent.resume_plan("succeeded"),
            [("revalidate", "succeeded")],
        )

    def test_rollback_chain_is_bounded(self):
        self.assertEqual(
            self.agent.rollback_plan("rollback-activated"),
            [
                ("revalidate", "rollback-activated"),
                ("execute", "rollback-recreated"),
                ("execute", "rollback-validated"),
                ("execute", "failed"),
            ],
        )
        self.assertEqual(
            self.agent.rollback_plan("failed"),
            [("revalidate", "failed")],
        )
        with self.assertRaises(ValueError):
            self.agent.rollback_plan("mirrored")


class StateContract(unittest.TestCase):
    def setUp(self):
        self.agent = load_agent()
        self.digest = "sha256:" + "a" * 64
        self.state = {
            "schema": 1,
            "version": "v1.2.3",
            "digest": self.digest,
            "commit": "b" * 40,
            "phase": "observed",
            "previous": None,
            "failure": None,
            "degradation": None,
            "rollback": None,
            "updated_at": "2026-07-19T22:00:00Z",
        }

    def test_atomic_state_round_trip_and_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "state.json"
            self.agent.write_state(path, self.state)
            self.assertEqual(self.agent.load_state(path), self.state)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertFalse(list(path.parent.glob(".state.json.*")))

    def test_validate_state_returns_a_deeply_immutable_snapshot(self):
        source = dict(
            self.state,
            previous={
                "version": "v1.2.2",
                "digest": "sha256:" + "c" * 64,
                "commit": "d" * 40,
            },
        )

        snapshot = self.agent.validate_state(source)
        source["phase"] = "failed"
        source["previous"]["commit"] = "e" * 40

        self.assertIsInstance(snapshot, self.agent.Snapshot)
        self.assertEqual(snapshot["phase"], "observed")
        self.assertEqual(snapshot["previous"]["commit"], "d" * 40)
        with self.assertRaises(TypeError):
            snapshot["phase"] = "failed"
        with self.assertRaises(TypeError):
            snapshot["previous"]["commit"] = "e" * 40

    def test_rejects_malformed_snapshot_fields(self):
        malformed = (
            ("schema", True),
            ("version", 1),
            ("digest", None),
            ("commit", []),
            ("phase", {}),
            ("failure", {}),
            ("degradation", []),
            ("rollback", 1),
            ("previous", {"version": "v1.2.2"}),
            (
                "previous",
                {
                    "version": "v1.2.2",
                    "digest": "sha256:bad",
                    "commit": "d" * 40,
                },
            ),
            ("updated_at", "2026-02-30T00:00:00Z"),
        )

        for field, value in malformed:
            with self.subTest(field=field, value=value):
                with self.assertRaises(ValueError):
                    self.agent.validate_state(dict(self.state, **{field: value}))

    def test_rejects_unknown_keys_and_invalid_identity(self):
        invalid = dict(self.state, extra=True)
        with self.assertRaises(ValueError):
            self.agent.validate_state(invalid)
        invalid = dict(self.state, digest="sha256:bad")
        with self.assertRaises(ValueError):
            self.agent.validate_state(invalid)

    def test_rejects_corrupt_json(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "state.json"
            path.write_text("{")
            with self.assertRaises((ValueError, json.JSONDecodeError)):
                self.agent.load_state(path)

    def test_transition_requires_exact_successor(self):
        advanced = self.agent.transition(self.state, "verified", "2026-07-19T22:01:00Z")
        self.assertEqual(advanced["phase"], "verified")
        self.assertEqual(advanced["updated_at"], "2026-07-19T22:01:00Z")
        with self.assertRaises(ValueError):
            self.agent.transition(self.state, "mirrored", "2026-07-19T22:01:00Z")

    def test_hard_failure_enters_rollback_only_after_activation(self):
        pre_activation = dict(self.state, phase="mirrored")
        with self.assertRaises(ValueError):
            self.agent.begin_rollback(
                pre_activation,
                "health gate failed",
                "2026-07-19T22:01:00Z",
            )
        activated = dict(self.state, phase="activated")
        rollback = self.agent.begin_rollback(
            activated,
            "health gate failed",
            "2026-07-19T22:01:00Z",
        )
        self.assertEqual(rollback["phase"], "rollback-activated")
        self.assertEqual(rollback["failure"], "health gate failed")


class ExternalReportingContract(unittest.TestCase):
    class SecretStore:
        def __init__(self, values):
            self.values = dict(values)
            self.paths = []

        def read(self, path):
            self.paths.append(path)
            try:
                return self.values[path]
            except KeyError as error:
                raise FileNotFoundError(path) from error

    class HttpClient:
        def __init__(self, responses):
            self.responses = list(responses)
            self.requests = []

        def send(self, request):
            self.requests.append(request)
            response = self.responses.pop(0)
            if isinstance(response, BaseException):
                raise response
            return response

    class Signer:
        def __init__(self, signature=b"signature"):
            self.signature = signature
            self.calls = []

        def sign(self, signing_input, pem):
            self.calls.append((signing_input, pem))
            if isinstance(self.signature, BaseException):
                raise self.signature
            return self.signature

    def setUp(self):
        self.agent = load_agent()
        self.digest = "sha256:" + "a" * 64
        self.clean = {
            "schema": 1,
            "version": "v1.2.3",
            "digest": self.digest,
            "commit": "b" * 40,
            "phase": "succeeded",
            "previous": {
                "version": "v1.2.2",
                "digest": "sha256:" + "c" * 64,
                "commit": "d" * 40,
            },
            "failure": None,
            "degradation": None,
            "rollback": None,
            "updated_at": "2026-07-19T22:00:00Z",
        }
        self.config = json.dumps({"app_id": 12345, "installation_id": 67890})
        self.pem = (
            "-----BEGIN PRIVATE KEY-----\n"
            "pem-secret-sentinel\n"
            "-----END PRIVATE KEY-----\n"
        )
        self.deploy_webhook = (
            "https://discord.com/api/webhooks/123456789/"
            "deploy-secret-sentinel-abcdefghijklmnop"
        )
        self.incident_webhook = (
            "https://discord.com/api/webhooks/987654321/"
            "incident-secret-sentinel-abcdefghijklmnop"
        )

    def response(self, status, body=None, headers=None):
        payload = b"" if body is None else json.dumps(body).encode()
        return self.agent.HttpResponse(status, headers or {}, payload)

    def token_response(self):
        return self.response(
            201,
            {
                "token": "ghs_" + "T" * 40,
                "expires_at": "2026-07-19T23:00:00Z",
                "permissions": {"checks": "write", "metadata": "read"},
                "repository_selection": "selected",
                "repositories": [
                    {"name": "servarr", "full_name": "ErikBPF/servarr"}
                ],
            },
        )

    def reporter(self, responses, values=None, signer=None):
        secret_values = {
            self.agent.GITHUB_APP_CONFIG: self.config,
            self.agent.GITHUB_APP_KEY: self.pem,
            self.agent.DISCORD_DEPLOYS_WEBHOOK: self.deploy_webhook,
            self.agent.DISCORD_INCIDENTS_WEBHOOK: self.incident_webhook,
        }
        if values is not None:
            secret_values.update(values)
        http = self.HttpClient(responses)
        secrets = self.SecretStore(secret_values)
        signer = signer or self.Signer()
        reporter = self.agent.ExternalReporter(
            http_client=http,
            signer=signer,
            clock=lambda: 1784500000,
            secrets=secrets,
        )
        return reporter, http, secrets, signer

    def test_terminal_report_is_immutable_and_bodies_embed_one_semantic_value(self):
        fixtures = []
        for phase, failure, degradation, rollback, conclusion in (
            ("succeeded", None, None, None, "success"),
            ("succeeded", None, "provider-auth-unavailable", None, "neutral"),
            ("failed", "health gate failed", None, "rollback-ok", "failure"),
            ("failed", "health gate failed", None, "rollback-failed", "failure"),
        ):
            state = dict(self.clean)
            state.update(
                phase=phase,
                failure=failure,
                degradation=degradation,
                rollback=rollback,
            )
            report = self.agent.terminal_report(state)
            github = self.agent.github_check_payload(report)
            discord = self.agent.discord_payload(report)
            normalized = report.to_dict()
            self.assertEqual(json.loads(github["output"]["summary"]), normalized)
            self.assertEqual(json.loads(discord["content"]), normalized)
            self.assertEqual(github["conclusion"], conclusion)
            fixtures.append(normalized)
            with self.assertRaises((AttributeError, dataclasses.FrozenInstanceError)):
                report.snapshot = None
        self.assertEqual(len(fixtures), 4)
        self.assertEqual(tuple(fixtures[0]), self.agent.STATE_FIELDS)

    def test_deliver_uses_fixed_github_check_and_minimal_installation_token(self):
        reporter, http, secrets, signer = self.reporter(
            [self.token_response(), self.response(201, {}), self.response(204)]
        )
        with mock.patch.dict(
            os.environ,
            {
                "GITHUB_API_HOST": "evil.invalid",
                "GITHUB_REPOSITORY": "attacker/repo",
                "GITHUB_TOKEN": "environment-secret-sentinel",
                "DISCORD_WEBHOOK": "https://evil.invalid/hook",
            },
        ):
            report = reporter.deliver(self.clean)

        self.assertEqual(len(http.requests), 3)
        token, check, discord = http.requests
        self.assertEqual(
            (token.method, token.host, token.endpoint),
            ("POST", "api.github.com", "/app/installations/67890/access_tokens"),
        )
        self.assertEqual(
            json.loads(token.body),
            {"repositories": ["servarr"], "permissions": {"checks": "write"}},
        )
        self.assertEqual(token.headers["User-Agent"], "kindle-release-agent/1")
        self.assertEqual(
            (check.method, check.host, check.endpoint),
            ("POST", "api.github.com", "/repos/ErikBPF/servarr/check-runs"),
        )
        self.assertEqual(json.loads(check.body)["head_sha"], self.clean["commit"])
        self.assertEqual(check.headers["User-Agent"], "kindle-release-agent/1")
        self.assertEqual(
            (discord.method, discord.host),
            ("POST", "discord.com"),
        )
        self.assertEqual(
            json.loads(json.loads(discord.body)["content"]),
            report.to_dict(),
        )
        self.assertEqual(
            secrets.paths,
            [
                self.agent.GITHUB_APP_CONFIG,
                self.agent.GITHUB_APP_KEY,
                self.agent.DISCORD_DEPLOYS_WEBHOOK,
            ],
        )
        self.assertEqual(len(signer.calls), 1)
        self.assertEqual(signer.calls[0][1], self.pem)
        request_text = " ".join(map(repr, http.requests))
        for secret in (
            self.pem,
            self.deploy_webhook,
            "ghs_" + "T" * 40,
            "environment-secret-sentinel",
        ):
            self.assertNotIn(secret, request_text)
        self.assertEqual(http.responses, [])

    def test_discord_routes_only_clean_success_to_deploys(self):
        fixtures = (
            (dict(self.clean), self.agent.DISCORD_DEPLOYS_WEBHOOK),
            (
                dict(self.clean, degradation="provider-auth-unavailable"),
                self.agent.DISCORD_INCIDENTS_WEBHOOK,
            ),
            (
                dict(self.clean, phase="failed", failure="runtime failed"),
                self.agent.DISCORD_INCIDENTS_WEBHOOK,
            ),
        )
        for state, expected_path in fixtures:
            with self.subTest(state=state):
                reporter, http, secrets, _ = self.reporter([self.response(204)])
                reporter.report_discord(self.agent.terminal_report(state))
                self.assertEqual(secrets.paths, [expected_path])
                self.assertEqual(len(http.requests), 1)

    def test_openssl_signer_passes_pem_on_stdin_and_no_secret_in_argv(self):
        completed = mock.Mock(stdout=b"signed", stderr=b"")
        with mock.patch.object(
            self.agent.subprocess,
            "run",
            return_value=completed,
        ) as run:
            signature = self.agent.OpenSslJwtSigner().sign(b"header.payload", self.pem)
        self.assertEqual(signature, b"signed")
        argv = run.call_args.args[0]
        self.assertEqual(run.call_args.kwargs["input"], self.pem.encode())
        self.assertNotIn(self.pem, " ".join(argv))
        self.assertNotIn("header.payload", " ".join(argv))
        self.assertTrue(run.call_args.kwargs["check"])

    def test_file_secret_store_requires_root_owned_regular_mode_0600(self):
        fake_path = pathlib.Path("/run/vault-agent/secret")
        regular = mock.Mock(st_mode=stat.S_IFREG | 0o600, st_uid=0)
        with mock.patch.object(self.agent.os, "lstat", return_value=regular), mock.patch.object(
            self.agent.pathlib.Path,
            "read_text",
            return_value="secret\n",
        ):
            self.assertEqual(self.agent.FileSecretStore().read(fake_path), "secret\n")
        for metadata in (
            mock.Mock(st_mode=stat.S_IFREG | 0o640, st_uid=0),
            mock.Mock(st_mode=stat.S_IFREG | 0o600, st_uid=1000),
            mock.Mock(st_mode=stat.S_IFLNK | 0o600, st_uid=0),
        ):
            with self.subTest(metadata=metadata), mock.patch.object(
                self.agent.os,
                "lstat",
                return_value=metadata,
            ):
                with self.assertRaises(self.agent.ExternalCredentialError) as caught:
                    self.agent.FileSecretStore().read(fake_path)
                self.assertEqual(str(caught.exception), "external credential unavailable")

    def test_credentials_token_responses_redirects_and_timeouts_fail_sanitized(self):
        sentinel = "credential-secret-sentinel"
        invalid_configs = (
            sentinel,
            json.dumps({"app_id": 1}),
            json.dumps({"app_id": 1, "installation_id": 2, "admin": True}),
            json.dumps({"app_id": "1", "installation_id": 2}),
        )
        for config in invalid_configs:
            with self.subTest(config=config):
                reporter, http, _, _ = self.reporter(
                    [],
                    {self.agent.GITHUB_APP_CONFIG: config},
                )
                with self.assertRaises(self.agent.ExternalCredentialError) as caught:
                    reporter.report_github(self.agent.terminal_report(self.clean))
                self.assertNotIn(sentinel, str(caught.exception))
                self.assertEqual(http.requests, [])

        malformed_tokens = (
            {"token": sentinel},
            {
                "token": sentinel,
                "expires_at": "not-a-time",
                "permissions": {"checks": "admin"},
                "repository_selection": "all",
            },
            {
                "token": "ghs_" + "T" * 40,
                "expires_at": "2026-07-19T23:00:00Z",
                "permissions": {
                    "checks": "write",
                    "metadata": "read",
                    "contents": "write",
                },
                "repository_selection": "selected",
                "repositories": [
                    {"name": "servarr", "full_name": "ErikBPF/servarr"},
                    {"name": "other", "full_name": "ErikBPF/other"},
                ],
            },
        )
        for body in malformed_tokens:
            with self.subTest(body=body):
                reporter, http, _, _ = self.reporter([self.response(201, body)])
                with self.assertRaises(self.agent.ExternalHttpError) as caught:
                    reporter.report_github(self.agent.terminal_report(self.clean))
                self.assertEqual(str(caught.exception), "external HTTP response invalid")
                self.assertNotIn(sentinel, str(caught.exception))
                self.assertEqual(len(http.requests), 1)

        for response in (
            self.response(302, headers={"Location": f"https://evil.invalid/{sentinel}"}),
            TimeoutError(sentinel),
        ):
            with self.subTest(response=response):
                reporter, http, _, _ = self.reporter([response])
                with self.assertRaises(self.agent.ExternalHttpError) as caught:
                    reporter.report_github(self.agent.terminal_report(self.clean))
                self.assertNotIn(sentinel, str(caught.exception))
                self.assertEqual(len(http.requests), 1)

    def test_signing_and_discord_url_fail_closed_without_secret_disclosure(self):
        sentinel = "signing-secret-sentinel"
        reporter, http, _, _ = self.reporter(
            [],
            signer=self.Signer(RuntimeError(sentinel)),
        )
        with self.assertRaises(self.agent.ExternalSigningError) as caught:
            reporter.report_github(self.agent.terminal_report(self.clean))
        self.assertEqual(str(caught.exception), "external signature unavailable")
        self.assertNotIn(sentinel, str(caught.exception))
        self.assertEqual(http.requests, [])

        for webhook in (
            f"http://discord.com/api/webhooks/1/{sentinel}",
            f"https://evil.invalid/api/webhooks/1/{sentinel}",
            f"https://discord.com/api/webhooks/1/{sentinel}?redirect=1",
        ):
            with self.subTest(webhook=webhook):
                reporter, http, _, _ = self.reporter(
                    [],
                    {self.agent.DISCORD_DEPLOYS_WEBHOOK: webhook},
                )
                with self.assertRaises(self.agent.ExternalCredentialError) as caught:
                    reporter.report_discord(self.agent.terminal_report(self.clean))
                self.assertNotIn(sentinel, str(caught.exception))
                self.assertEqual(http.requests, [])

    def test_hostile_snapshot_is_rejected_before_any_request(self):
        reporter, http, _, _ = self.reporter([])
        hostile = dict(self.clean, unexpected="secret-sentinel")
        with self.assertRaises(ValueError):
            reporter.deliver(hostile)
        self.assertEqual(http.requests, [])
        intermediate = dict(self.clean, phase="validated")
        with self.assertRaises(ValueError):
            reporter.deliver(intermediate)
        self.assertEqual(http.requests, [])


class ProjectionContract(unittest.TestCase):
    def setUp(self):
        self.agent = load_agent()
        self.state = {
            "schema": 1,
            "version": "v1.2.3",
            "digest": "sha256:" + "a" * 64,
            "commit": "b" * 40,
            "phase": "failed",
            "previous": None,
            "failure": 'bad "quote"\\path\nnext',
            "degradation": "provider unavailable",
            "rollback": "restored previous release",
            "updated_at": "2026-07-20T12:34:56Z",
        }

    def test_journal_and_prometheus_are_equivalent_safe_projections(self):
        snapshot = self.agent.validate_state(self.state)

        event_text = self.agent.render_journal_event(snapshot)
        event = json.loads(event_text)
        self.assertNotIn("\n", event_text)
        self.assertEqual(event["event"], "kindle-release-agent-snapshot")
        for field in self.agent.STATE_FIELDS:
            self.assertEqual(event[field], snapshot.to_dict()[field])

        metrics = self.agent.render_prometheus(snapshot)
        self.assertIn(
            'failure="bad \\"quote\\"\\\\path\\nnext"',
            metrics,
        )
        self.assertIn('degradation="provider unavailable"', metrics)
        self.assertIn('rollback="restored previous release"', metrics)
        expected_epoch = int(
            datetime.datetime(
                2026,
                7,
                20,
                12,
                34,
                56,
                tzinfo=datetime.timezone.utc,
            ).timestamp()
        )
        self.assertIn(
            f"kindle_release_agent_snapshot_updated_seconds {expected_epoch}\n",
            metrics,
        )
        samples = [line for line in metrics.splitlines() if not line.startswith("#")]
        self.assertEqual(len(samples), 2)
        self.assertTrue(samples[0].endswith("} 1"))
        self.assertEqual(len(samples[1].split()), 2)

    def test_persist_snapshot_orders_one_canonical_value_across_surfaces(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            state_path = root / "state.json"
            metric_path = root / "kindle-release-agent.prom"
            output = io.StringIO()
            calls = []
            original_write_state = self.agent.write_state
            original_render_event = self.agent.render_journal_event
            original_write_metric = self.agent.write_metric

            def write_state(path, snapshot):
                calls.append(("state", snapshot))
                original_write_state(path, snapshot)

            def render_event(snapshot):
                self.assertEqual(self.agent.load_state(state_path), snapshot)
                self.assertFalse(metric_path.exists())
                calls.append(("event", snapshot))
                return original_render_event(snapshot)

            def write_metric(path, snapshot):
                self.assertTrue(output.getvalue())
                calls.append(("metric", snapshot))
                original_write_metric(path, snapshot)

            with (
                mock.patch.object(
                    self.agent,
                    "write_state",
                    side_effect=write_state,
                ),
                mock.patch.object(
                    self.agent,
                    "render_journal_event",
                    side_effect=render_event,
                ),
                mock.patch.object(
                    self.agent,
                    "write_metric",
                    side_effect=write_metric,
                ),
                contextlib.redirect_stdout(output),
            ):
                snapshot = self.agent.persist_snapshot(
                    state_path,
                    metric_path,
                    self.state,
                )

            self.assertEqual([name for name, _ in calls], ["state", "event", "metric"])
            self.assertTrue(all(value is snapshot for _, value in calls))
            self.assertEqual(self.agent.load_state(state_path), snapshot)
            self.assertEqual(
                metric_path.read_text(),
                self.agent.render_prometheus(snapshot),
            )
            self.assertEqual(len(output.getvalue().splitlines()), 1)

    def test_state_and_metric_use_the_shared_atomic_writer(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            state_path = root / "state" / "state.json"
            metric_path = root / "textfile" / "kindle-release-agent.prom"

            self.agent.write_state(state_path, self.state)
            self.agent.write_metric(metric_path, self.state)

            self.assertEqual(self.agent.load_state(state_path), self.state)
            self.assertEqual(metric_path.read_text(), self.agent.render_prometheus(self.state))
            self.assertEqual(state_path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(metric_path.stat().st_mode & 0o777, 0o644)
            self.assertEqual(state_path.parent.stat().st_mode & 0o777, 0o700)
            self.assertEqual(metric_path.parent.stat().st_mode & 0o777, 0o755)
            self.assertFalse(list(root.rglob(".*.tmp-*")))

    def test_atomic_metric_failures_never_expose_partial_content(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            path = root / "kindle-release-agent.prom"
            old = "kindle_release_agent_snapshot_info 0\n"
            expected = self.agent.render_prometheus(self.state)
            failures = (
                (
                    "temp",
                    lambda: mock.patch.object(
                        self.agent.tempfile,
                        "mkstemp",
                        side_effect=OSError("temp failed"),
                    ),
                ),
                (
                    "write",
                    lambda: mock.patch.object(
                        self.agent,
                        "_write_payload",
                        side_effect=OSError("write failed"),
                    ),
                ),
                (
                    "file-fsync",
                    lambda: mock.patch.object(
                        self.agent.os,
                        "fsync",
                        side_effect=OSError("file fsync failed"),
                    ),
                ),
                (
                    "rename",
                    lambda: mock.patch.object(
                        self.agent.os,
                        "replace",
                        side_effect=OSError("rename failed"),
                    ),
                ),
                (
                    "directory-fsync",
                    lambda: mock.patch.object(
                        self.agent.os,
                        "fsync",
                        side_effect=(None, OSError("directory fsync failed")),
                    ),
                ),
            )

            for stage, patcher in failures:
                with self.subTest(stage=stage):
                    path.write_text(old)
                    with patcher(), self.assertRaises(OSError):
                        self.agent.write_metric(path, self.state)
                    self.assertIn(path.read_text(), (old, expected))
                    self.assertFalse(list(root.glob(".*.tmp-*")))


class RunnerContract(unittest.TestCase):
    class Operations:
        def __init__(self, fail=None):
            self.calls = []
            self.fail = fail

        def revalidate(self, phase, state):
            self.calls.append(("revalidate", phase))
            if self.fail == ("revalidate", phase):
                raise RuntimeError("injected")

        def execute(self, phase, state):
            self.calls.append(("execute", phase))
            if self.fail == ("execute", phase):
                raise RuntimeError("injected")

    def setUp(self):
        self.agent = load_agent()
        self.state = {
            "schema": 1,
            "version": "v1.2.3",
            "digest": "sha256:" + "a" * 64,
            "commit": "b" * 40,
            "phase": "mirrored",
            "previous": {
                "version": "v1.2.2",
                "digest": "sha256:" + "c" * 64,
                "commit": "d" * 40,
            },
            "failure": None,
            "degradation": None,
            "rollback": None,
            "updated_at": "2026-07-19T22:00:00Z",
        }

    def test_forward_runner_persists_after_each_successful_action(self):
        operations = self.Operations()
        persisted = []
        result = self.agent.run_forward(
            self.state,
            operations,
            lambda state: persisted.append(state["phase"]),
            lambda: "2026-07-19T22:01:00Z",
        )
        self.assertEqual(result["phase"], "succeeded")
        self.assertEqual(
            operations.calls,
            [
                ("revalidate", "mirrored"),
                ("execute", "activated"),
                ("execute", "recreated"),
                ("execute", "validated"),
                ("execute", "succeeded"),
            ],
        )
        self.assertEqual(
            persisted,
            ["activated", "recreated", "validated", "succeeded"],
        )

    def test_pre_activation_failure_stops_without_rollback(self):
        operations = self.Operations(fail=("execute", "activated"))
        persisted = []
        with self.assertRaisesRegex(RuntimeError, "injected"):
            self.agent.run_forward(
                self.state,
                operations,
                lambda state: persisted.append(state["phase"]),
                lambda: "2026-07-19T22:01:00Z",
            )
        self.assertEqual(persisted, [])
        self.assertEqual(operations.calls[-1], ("execute", "activated"))

    def test_post_activation_failure_runs_bounded_rollback(self):
        operations = self.Operations(fail=("execute", "recreated"))
        persisted = []
        result = self.agent.run_forward(
            self.state,
            operations,
            lambda state: persisted.append(state["phase"]),
            lambda: "2026-07-19T22:01:00Z",
        )
        self.assertEqual(result["phase"], "failed")
        self.assertEqual(
            operations.calls[-3:],
            [
                ("execute", "rollback-recreated"),
                ("execute", "rollback-validated"),
                ("execute", "failed"),
            ],
        )
        self.assertEqual(
            persisted,
            [
                "activated",
                "rollback-activated",
                "rollback-recreated",
                "rollback-validated",
                "failed",
            ],
        )


class ContinuityFailureInjectionContract(unittest.TestCase):
    def setUp(self):
        self.agent = load_agent()
        self.state = {
            "schema": 1,
            "version": "v1.2.3",
            "digest": "sha256:" + "a" * 64,
            "commit": "b" * 40,
            "phase": "activated",
            "previous": {
                "version": "v1.2.2",
                "digest": "sha256:" + "c" * 64,
                "commit": "d" * 40,
            },
            "failure": None,
            "degradation": None,
            "rollback": None,
            "updated_at": "2026-07-20T12:00:00Z",
        }

    def test_successful_rollback_records_terminal_result(self):
        operations = mock.Mock()
        persisted = []
        result = self.agent.run_rollback(
            self.state,
            "runtime gate failed",
            operations,
            persisted.append,
            lambda: "2026-07-20T12:01:00Z",
        )
        self.assertEqual(result["phase"], "failed")
        self.assertEqual(result["failure"], "runtime gate failed")
        self.assertEqual(result["rollback"], "succeeded")
        self.assertEqual(persisted[-1], result)

    def test_rollback_failure_is_bounded_and_persisted(self):
        for failed_phase in (
            "rollback-activated",
            "rollback-recreated",
            "rollback-validated",
        ):
            with self.subTest(failed_phase=failed_phase):
                operations = mock.Mock()

                def execute(phase, _state):
                    if phase == failed_phase:
                        raise RuntimeError("secret failure detail")

                operations.execute.side_effect = execute
                persisted = []
                result = self.agent.run_rollback(
                    self.state,
                    "runtime gate failed",
                    operations,
                    persisted.append,
                    lambda: "2026-07-20T12:01:00Z",
                )
                self.assertEqual(result["phase"], "failed")
                self.assertEqual(result["failure"], "runtime gate failed")
                self.assertEqual(result["rollback"], "failed")
                self.assertEqual(result["previous"], self.state["previous"])
                self.assertEqual(persisted[-1], result)
                attempted = [
                    call.args[0] for call in operations.execute.call_args_list
                ]
                self.assertEqual(attempted[-1], failed_phase)
                self.assertEqual(attempted.count(failed_phase), 1)

    def test_persisted_rollback_phase_revalidates_then_resumes(self):
        for phase in self.agent.ROLLBACK_PHASES:
            with self.subTest(phase=phase):
                state = self.agent.validate_state(
                    dict(
                        self.state,
                        phase=phase,
                        failure="runtime gate failed",
                        rollback="succeeded" if phase == "failed" else None,
                    )
                )
                operations = mock.Mock()
                persisted = []
                result = self.agent.resume_execution(
                    state,
                    operations,
                    persisted.append,
                    lambda: "2026-07-20T12:01:00Z",
                )
                operations.revalidate.assert_called_once_with(phase, state)
                self.assertEqual(result["phase"], "failed")
                self.assertEqual(result["rollback"], "succeeded")
                if phase == "failed":
                    operations.execute.assert_not_called()


class ObservationContract(unittest.TestCase):
    class Runner:
        def __init__(self, outputs):
            self.outputs = iter(outputs)
            self.calls = []

        def run(self, argv):
            self.calls.append(argv)
            return next(self.outputs)

    def setUp(self):
        self.agent = load_agent()
        self.previous = "a" * 40
        self.target = "b" * 40
        self.digest = "sha256:" + "c" * 64
        self.compose = (
            "services:\n  kindle-dash:\n"
            "    image: harbor.homelab.pastelariadev.com/library/"
            f"kindle-dash:v1.2.3@{self.digest}\n"
        )

    def test_fetches_only_main_and_reads_candidate_without_checkout(self):
        runner = self.Runner(
            [
                "",
                self.target + "\n",
                "",
                self.target + "\n",
                self.agent.COMPOSE_PATH + "\n",
                self.compose,
            ]
        )
        candidate = self.agent.observe_candidate(runner, self.previous)
        self.assertEqual(candidate["commit"], self.target)
        git = [
            "runuser", "-u", self.agent.DEPLOY_USER, "--",
            "git", "-C", str(self.agent.SERVARR_REPO),
        ]
        self.assertEqual(
            runner.calls,
            [
                [
                    *git,
                    "fetch",
                    "--prune",
                    "origin",
                    "main",
                ],
                [
                    *git,
                    "rev-parse",
                    "refs/remotes/origin/main",
                ],
                [
                    *git,
                    "merge-base",
                    "--is-ancestor",
                    self.previous,
                    self.target,
                ],
                [
                    *git,
                    "rev-list",
                    "--reverse",
                    f"{self.previous}..{self.target}",
                    "--",
                    self.agent.COMPOSE_PATH,
                ],
                [
                    *git,
                    "diff-tree",
                    "--no-commit-id",
                    "--name-only",
                    "-r",
                    self.target,
                ],
                [
                    *git,
                    "show",
                    f"{self.target}:{self.agent.COMPOSE_PATH}",
                ],
            ],
        )
        self.assertFalse(any("reset" in call for call in runner.calls))

    def test_observation_rejects_unrelated_diff(self):
        runner = self.Runner(
            [
                "",
                self.target,
                "",
                self.target,
                self.agent.COMPOSE_PATH + "\nother.yml\n",
                self.compose,
            ]
        )
        with self.assertRaises(ValueError):
            self.agent.observe_candidate(runner, self.previous)

    def test_observation_ignores_advances_without_compose_change(self):
        runner = self.Runner(["", self.target, "", ""])
        self.assertIsNone(self.agent.observe_candidate(runner, self.previous))

    def test_observation_returns_none_when_main_has_not_advanced(self):
        runner = self.Runner(["", self.previous + "\n"])
        self.assertIsNone(self.agent.observe_candidate(runner, self.previous))
        self.assertEqual(len(runner.calls), 2)


class VerificationContract(unittest.TestCase):
    class Runner:
        def __init__(self, outputs):
            self.outputs = iter(outputs)
            self.calls = []

        def run(self, argv):
            self.calls.append(argv)
            return next(self.outputs)

    def setUp(self):
        self.agent = load_agent()
        self.digest = "sha256:" + "a" * 64
        self.candidate = {
            "commit": "b" * 40,
            "version": "v1.2.3",
            "digest": self.digest,
        }

    def test_verifies_exact_workflow_identity_and_tag_digest(self):
        runner = self.Runner(["", self.digest + "\n"])
        self.agent.verify_release(runner, self.candidate)
        self.assertEqual(
            runner.calls,
            [
                [
                    "cosign",
                    "verify",
                    "--certificate-identity",
                    self.agent.COSIGN_IDENTITY,
                    "--certificate-oidc-issuer",
                    self.agent.COSIGN_ISSUER,
                    f"{self.agent.GHCR_IMAGE}@{self.digest}",
                ],
                [
                    "skopeo",
                    "inspect",
                    "--format",
                    "{{.Digest}}",
                    f"docker://{self.agent.GHCR_IMAGE}:v1.2.3",
                ],
            ],
        )

    def test_tag_digest_mismatch_halts(self):
        runner = self.Runner(["", "sha256:" + "c" * 64])
        with self.assertRaisesRegex(ValueError, "tag digest mismatch"):
            self.agent.verify_release(runner, self.candidate)


class MirrorContract(unittest.TestCase):
    class Runner:
        def __init__(self):
            self.calls = []

        def run_env(self, argv, environment):
            self.calls.append((argv, environment))
            return ""

    def setUp(self):
        self.agent = load_agent()
        self.candidate = {
            "commit": "b" * 40,
            "version": "v1.2.3",
            "digest": "sha256:" + "a" * 64,
        }

    def test_reads_literal_robot_values_without_shell_evaluation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "harbor.env"
            path.write_text(
                "HARBOR_ADMIN_PASSWORD=ignored\n"
                "HARBOR_ROBOT_USER=robot$library+mirror\n"
                "HARBOR_ROBOT_SECRET=value$with spaces\n"
            )
            self.assertEqual(
                self.agent.load_harbor_robot(path),
                {
                    "HARBOR_ROBOT_USER": "robot$library+mirror",
                    "HARBOR_ROBOT_SECRET": "value$with spaces",
                },
            )

    def test_mirror_uses_only_fixed_script_and_robot_environment(self):
        runner = self.Runner()
        environment = {
            "HARBOR_ROBOT_USER": "robot$library+mirror",
            "HARBOR_ROBOT_SECRET": "secret",
        }
        self.agent.mirror_release(runner, self.candidate, environment)
        self.assertEqual(
            runner.calls,
            [
                (
                    [
                        str(self.agent.HARBOR_MIRROR_SCRIPT),
                        "v1.2.3",
                        self.candidate["digest"],
                    ],
                    environment,
                )
            ],
        )
        self.assertNotIn("HARBOR_ADMIN_PASSWORD", runner.calls[0][1])

    def test_missing_or_duplicate_robot_key_halts(self):
        for text in (
            "HARBOR_ROBOT_USER=user\n",
            "HARBOR_ROBOT_USER=one\nHARBOR_ROBOT_USER=two\n"
            "HARBOR_ROBOT_SECRET=secret\n",
        ):
            with tempfile.TemporaryDirectory() as directory:
                path = pathlib.Path(directory) / "harbor.env"
                path.write_text(text)
                with self.assertRaises(ValueError):
                    self.agent.load_harbor_robot(path)


class ActivationContract(unittest.TestCase):
    class Runner:
        def __init__(self):
            self.calls = []

        def run(self, argv):
            self.calls.append(argv)
            return ""

    def setUp(self):
        self.agent = load_agent()
        self.commit = "b" * 40

    def test_activation_uses_exact_published_commit(self):
        runner = self.Runner()
        self.agent.activate_revision(runner, self.commit)
        git = ["runuser", "-u", "erik", "--", "git", "-C", str(self.agent.SERVARR_REPO)]
        self.assertEqual(
            runner.calls,
            [
                git + ["cat-file", "-e", f"{self.commit}^{{commit}}"],
                git
                + [
                    "merge-base",
                    "--is-ancestor",
                    self.commit,
                    "refs/remotes/origin/main",
                ],
                git + ["reset", "--hard", self.commit],
            ],
        )

    def test_recreate_targets_only_kindle_unit(self):
        runner = self.Runner()
        self.agent.recreate_kindle(runner, 1000)
        self.assertEqual(
            runner.calls,
            [
                [
                    "runuser",
                    "-u",
                    "erik",
                    "--",
                    "env",
                    "XDG_RUNTIME_DIR=/run/user/1000",
                    "systemctl",
                    "--user",
                    "restart",
                    self.agent.KINDLE_UNIT,
                ]
            ],
        )

    def test_malformed_commit_halts_before_command(self):
        runner = self.Runner()
        with self.assertRaises(ValueError):
            self.agent.activate_revision(runner, "main")
        self.assertEqual(runner.calls, [])


class RuntimeGateContract(unittest.TestCase):
    class Runner:
        def __init__(self, outputs, png=b"\x89PNG\r\n\x1a\nrest"):
            self.outputs = iter(outputs)
            self.png = png
            self.calls = []

        def run(self, argv):
            self.calls.append(argv)
            return next(self.outputs)

        def run_bytes(self, argv):
            self.calls.append(argv)
            return self.png

    def setUp(self):
        self.agent = load_agent()
        self.digest = "sha256:" + "a" * 64
        self.image_id = "sha256:" + "b" * 64
        self.inspect = json.dumps(
            [
                {
                    "Image": self.image_id,
                    "Config": {
                        "Labels": {"com.docker.compose.project": "kindle-dash"}
                    },
                    "State": {"Health": {"Status": "healthy"}},
                    "Mounts": [
                        {
                            "Name": "discovery_kindle_dash_data",
                            "Destination": "/data",
                        }
                    ],
                }
            ]
        )
        self.image = json.dumps(
            [
                {
                    "RepoDigests": [
                        "harbor.homelab.pastelariadev.com/library/"
                        f"kindle-dash@{self.digest}"
                    ]
                }
            ]
        )

    def test_all_hard_runtime_gates_pass_together(self):
        runner = self.Runner([self.inspect, self.image])
        self.agent.validate_runtime(runner, self.digest)
        self.assertEqual(runner.calls[0], ["docker", "inspect", "kindle-dash"])
        self.assertEqual(
            runner.calls[1],
            ["docker", "image", "inspect", self.image_id],
        )
        self.assertEqual(
            runner.calls[2],
            [
                "curl",
                "--fail",
                "--silent",
                "--show-error",
                "--resolve",
                "kindle.homelab.pastelariadev.com:80:192.168.10.210",
                self.agent.KINDLE_URL,
            ],
        )

    def test_starting_health_converges_before_other_gates(self):
        starting = json.loads(self.inspect)
        starting[0]["State"]["Health"]["Status"] = "starting"
        runner = self.Runner([json.dumps(starting), self.inspect, self.image])
        with mock.patch.object(self.agent.time, "sleep") as sleep:
            self.agent.validate_runtime(runner, self.digest)
        sleep.assert_called_once_with(2)
        self.assertEqual(runner.calls[:2], [
            ["docker", "inspect", "kindle-dash"],
            ["docker", "inspect", "kindle-dash"],
        ])

    def test_each_hard_gate_fails_closed(self):
        cases = {
            "health": lambda value: value[0]["State"]["Health"].update(
                Status="unhealthy"
            ),
            "owner": lambda value: value[0]["Config"]["Labels"].update(
                {"com.docker.compose.project": "foreign"}
            ),
            "volume": lambda value: value[0]["Mounts"].clear(),
        }
        for name, mutate in cases.items():
            inspect = json.loads(self.inspect)
            mutate(inspect)
            with self.subTest(name=name):
                runner = self.Runner([json.dumps(inspect), self.image])
                with self.assertRaises(ValueError):
                    self.agent.validate_runtime(runner, self.digest)
        with self.assertRaises(ValueError):
            self.agent.validate_runtime(
                self.Runner([self.inspect, json.dumps([{"RepoDigests": []}])]),
                self.digest,
            )
        with self.assertRaises(ValueError):
            self.agent.validate_runtime(
                self.Runner([self.inspect, self.image], png=b"not-png"),
                self.digest,
            )


class SubprocessBoundaryContract(unittest.TestCase):
    def setUp(self):
        self.agent = load_agent()

    @mock.patch("subprocess.run")
    def test_text_commands_are_argv_only_and_checked(self, run):
        run.return_value.stdout = "output\n"
        runner = self.agent.SubprocessRunner()
        self.assertEqual(runner.run(["git", "status"]), "output\n")
        run.assert_called_once_with(
            ["git", "status"],
            check=True,
            stdout=self.agent.subprocess.PIPE,
            text=True,
        )
        self.assertNotIn("shell", run.call_args.kwargs)

    @mock.patch("subprocess.run")
    def test_environment_is_overlay_not_replacement(self, run):
        run.return_value.stdout = "ok"
        runner = self.agent.SubprocessRunner()
        with mock.patch.dict(self.agent.os.environ, {"PATH": "/fixed"}, clear=True):
            runner.run_env(["mirror"], {"HARBOR_ROBOT_USER": "robot"})
        environment = run.call_args.kwargs["env"]
        self.assertEqual(environment["PATH"], "/fixed")
        self.assertEqual(environment["HARBOR_ROBOT_USER"], "robot")
        self.assertEqual(run.call_args.kwargs["text"], True)
        self.assertNotIn("shell", run.call_args.kwargs)

    @mock.patch("subprocess.run")
    def test_binary_command_does_not_decode_png(self, run):
        run.return_value.stdout = b"\x89PNG"
        runner = self.agent.SubprocessRunner()
        self.assertEqual(runner.run_bytes(["curl"]), b"\x89PNG")
        self.assertNotIn("text", run.call_args.kwargs)


class SystemOperationsContract(unittest.TestCase):
    def setUp(self):
        self.agent = load_agent()
        self.runner = object()
        self.operations = self.agent.SystemOperations(
            self.runner,
            uid=1000,
            harbor_env=pathlib.Path("/run/vault-agent/harbor.env"),
        )
        self.state = {
            "schema": 1,
            "version": "v1.2.3",
            "digest": "sha256:" + "a" * 64,
            "commit": "b" * 40,
            "phase": "observed",
            "previous": {
                "version": "v1.2.2",
                "digest": "sha256:" + "c" * 64,
                "commit": "d" * 40,
            },
            "failure": None,
            "degradation": None,
            "rollback": None,
            "updated_at": "2026-07-19T22:00:00Z",
        }

    def test_verified_phase_uses_candidate_identity(self):
        # Patch the function in the operations instance's module, not this
        # separately loaded test module.
        with mock.patch.object(self.agent, "verify_release") as verify:
            self.operations.execute("verified", self.state)
        verify.assert_called_once_with(
            self.runner,
            {
                "version": self.state["version"],
                "digest": self.state["digest"],
                "commit": self.state["commit"],
            },
        )

    def test_mirror_phase_uses_root_only_robot_render(self):
        credentials = {
            "HARBOR_ROBOT_USER": "robot",
            "HARBOR_ROBOT_SECRET": "secret",
        }
        with (
            mock.patch.object(
                self.agent,
                "load_harbor_robot",
                return_value=credentials,
            ) as load,
            mock.patch.object(self.agent, "mirror_release") as mirror,
        ):
            self.operations.execute("mirrored", self.state)
        load.assert_called_once_with(pathlib.Path("/run/vault-agent/harbor.env"))
        mirror.assert_called_once_with(
            self.runner,
            {
                "version": self.state["version"],
                "digest": self.state["digest"],
                "commit": self.state["commit"],
            },
            credentials,
        )

    def test_forward_activation_recreation_and_validation_are_fixed(self):
        with (
            mock.patch.object(self.agent, "activate_revision") as activate,
            mock.patch.object(self.agent, "recreate_kindle") as recreate,
            mock.patch.object(self.agent, "validate_runtime") as validate,
        ):
            self.operations.execute("activated", self.state)
            self.operations.execute("recreated", self.state)
            self.operations.execute("validated", self.state)
            self.operations.execute("succeeded", self.state)
        activate.assert_called_once_with(self.runner, self.state["commit"])
        recreate.assert_called_once_with(self.runner, 1000)
        validate.assert_called_once_with(self.runner, self.state["digest"])

    def test_fixed_drill_fails_validation_after_recreate(self):
        with mock.patch.object(self.agent, "FAIL_AFTER_RECREATE", True):
            with self.assertRaisesRegex(RuntimeError, "controlled post-recreate"):
                self.operations.execute("validated", self.state)

    def test_rollback_uses_only_previous_identity(self):
        with (
            mock.patch.object(self.agent, "activate_revision") as activate,
            mock.patch.object(self.agent, "recreate_kindle") as recreate,
            mock.patch.object(self.agent, "validate_runtime") as validate,
        ):
            self.operations.execute("rollback-activated", self.state)
            self.operations.execute("rollback-recreated", self.state)
            self.operations.execute("rollback-validated", self.state)
            self.operations.execute("failed", self.state)
        activate.assert_called_once_with(
            self.runner,
            self.state["previous"]["commit"],
        )
        recreate.assert_called_once_with(self.runner, 1000)
        validate.assert_called_once_with(
            self.runner,
            self.state["previous"]["digest"],
        )

    def test_revalidation_matches_each_forward_phase_proof(self):
        candidate = {
            "version": self.state["version"],
            "digest": self.state["digest"],
            "commit": self.state["commit"],
        }
        with (
            mock.patch.object(
                self.agent,
                "observe_candidate",
                return_value=candidate,
            ) as observe,
            mock.patch.object(self.agent, "verify_release") as verify,
            mock.patch.object(self.agent, "verify_harbor") as harbor,
            mock.patch.object(self.agent, "verify_active_commit") as active,
            mock.patch.object(self.agent, "validate_runtime") as runtime,
        ):
            for phase in self.agent.FORWARD_PHASES:
                state = dict(self.state, phase=phase)
                self.operations.revalidate(phase, state)
        observe.assert_called_once_with(
            self.runner,
            self.state["previous"]["commit"],
        )
        self.assertGreaterEqual(verify.call_count, 2)
        harbor.assert_called_once_with(
            self.runner,
            self.state["digest"],
        )
        self.assertGreaterEqual(active.call_count, 4)
        self.assertGreaterEqual(runtime.call_count, 3)

    def test_revalidation_rejects_changed_observed_candidate(self):
        changed = {
            "version": "v9.9.9",
            "digest": "sha256:" + "e" * 64,
            "commit": "f" * 40,
        }
        with mock.patch.object(
            self.agent,
            "observe_candidate",
            return_value=changed,
        ):
            with self.assertRaisesRegex(ValueError, "observed candidate drift"):
                self.operations.revalidate("observed", self.state)


class BootstrapContract(unittest.TestCase):
    class Runner:
        def __init__(self, outputs, *, png=b"\x89PNG\r\n\x1a\nrest", fail_at=None):
            self.outputs = list(outputs)
            self.png = png
            self.fail_at = fail_at
            self.calls = []
            self.environment_calls = []

        def _fail_if_requested(self):
            if self.fail_at == len(self.calls) - 1:
                raise RuntimeError("injected bootstrap gate failure")

        def run(self, argv):
            self.calls.append(argv)
            self._fail_if_requested()
            return self.outputs[len(self.calls) - 1]

        def run_bytes(self, argv):
            self.calls.append(argv)
            self._fail_if_requested()
            return self.png

        def run_env(self, argv, environment):
            self.environment_calls.append((argv, environment))
            raise AssertionError("bootstrap must not use credential-bearing commands")

    def setUp(self):
        self.agent = load_agent()
        reporting = mock.patch.object(
            self.agent,
            "report_terminal",
            side_effect=lambda result, *_args: result,
        )
        reporting.start()
        self.addCleanup(reporting.stop)
        self.commit = "b" * 40
        self.digest = "sha256:" + "a" * 64
        self.image_id = "sha256:" + "c" * 64
        self.compose = (
            "services:\n  kindle-dash:\n"
            "    image: harbor.homelab.pastelariadev.com/library/"
            f"kindle-dash:v1.2.3@{self.digest}\n"
        )
        self.container = {
            "Image": self.image_id,
            "Config": {"Labels": {"com.docker.compose.project": "kindle-dash"}},
            "State": {"Health": {"Status": "healthy"}},
            "Mounts": [
                {
                    "Name": "discovery_kindle_dash_data",
                    "Destination": "/data",
                }
            ],
        }
        self.image = {
            "RepoDigests": [
                "harbor.homelab.pastelariadev.com/library/"
                f"kindle-dash@{self.digest}"
            ]
        }

    def outputs(self):
        return [
            "",
            self.commit + "\n",
            "",
            self.compose,
            "",
            self.digest + "\n",
            self.digest + "\n",
            "compose-blob\n",
            "compose-blob\n",
            json.dumps([self.container]),
            json.dumps([self.image]),
        ]

    def test_adopts_active_live_tuple_once_after_every_read_only_gate(self):
        runner = self.Runner(self.outputs())
        persisted = []
        events = []

        def now():
            self.assertEqual(len(runner.calls), 12)
            events.append("clock")
            return "2026-07-20T10:11:12Z"

        def persist(state):
            self.assertEqual(events, ["clock"])
            persisted.append(state)

        state = self.agent.adopt_live_baseline(runner, persist, now)

        self.assertEqual(
            state,
            {
                "schema": 1,
                "version": "v1.2.3",
                "digest": self.digest,
                "commit": self.commit,
                "phase": "succeeded",
                "previous": None,
                "failure": None,
                "degradation": None,
                "rollback": None,
                "updated_at": "2026-07-20T10:11:12Z",
            },
        )
        self.assertEqual(persisted, [state])
        self.assertEqual(
            runner.calls[:4],
            [
                [
                    "runuser",
                    "-u",
                    "erik",
                    "--",
                    "git",
                    "-C",
                    str(self.agent.SERVARR_REPO),
                    "fetch",
                    "origin",
                    "main",
                ],
                [
                    "runuser",
                    "-u",
                    "erik",
                    "--",
                    "git",
                    "-C",
                    str(self.agent.SERVARR_REPO),
                    "rev-parse",
                    "HEAD",
                ],
                [
                    "runuser",
                    "-u",
                    "erik",
                    "--",
                    "git",
                    "-C",
                    str(self.agent.SERVARR_REPO),
                    "merge-base",
                    "--is-ancestor",
                    self.commit,
                    "refs/remotes/origin/main",
                ],
                [
                    "runuser",
                    "-u",
                    "erik",
                    "--",
                    "git",
                    "-C",
                    str(self.agent.SERVARR_REPO),
                    "show",
                    f"{self.commit}:{self.agent.COMPOSE_PATH}",
                ],
            ],
        )
        forbidden = {
            "reset",
            "restart",
            "recreate",
            "rollback",
            "prune",
            "--prune",
            "volume-rm",
        }
        flattened = {argument for call in runner.calls for argument in call}
        self.assertTrue(forbidden.isdisjoint(flattened))
        self.assertFalse(
            any(str(self.agent.HARBOR_MIRROR_SCRIPT) in call for call in runner.calls)
        )
        self.assertEqual(runner.environment_calls, [])

    def test_each_subprocess_or_png_gate_failure_prevents_persistence(self):
        for fail_at in range(12):
            with self.subTest(fail_at=fail_at):
                runner = self.Runner(self.outputs(), fail_at=fail_at)
                persisted = []
                with self.assertRaises(RuntimeError):
                    self.agent.adopt_live_baseline(
                        runner,
                        persisted.append,
                        lambda: "2026-07-20T10:11:12Z",
                    )
                self.assertEqual(persisted, [])

    def test_malformed_commit_and_noncanonical_pin_prevent_persistence(self):
        invalid_cases = {
            "commit": (1, "main\n"),
            "missing-pin": (3, "services: {}\n"),
            "duplicate-pin": (3, self.compose + self.compose),
        }
        for name, (index, value) in invalid_cases.items():
            with self.subTest(name=name):
                outputs = self.outputs()
                outputs[index] = value
                persisted = []
                with self.assertRaises(ValueError):
                    self.agent.adopt_live_baseline(
                        self.Runner(outputs),
                        persisted.append,
                        lambda: "2026-07-20T10:11:12Z",
                    )
                self.assertEqual(persisted, [])

    def test_each_runtime_identity_gate_prevents_persistence(self):
        cases = {}
        unhealthy = json.loads(json.dumps(self.container))
        unhealthy["State"]["Health"]["Status"] = "unhealthy"
        cases["health"] = (unhealthy, self.image, b"\x89PNG\r\n\x1a\n")
        foreign = json.loads(json.dumps(self.container))
        foreign["Config"]["Labels"]["com.docker.compose.project"] = "foreign"
        cases["owner"] = (foreign, self.image, b"\x89PNG\r\n\x1a\n")
        unmounted = json.loads(json.dumps(self.container))
        unmounted["Mounts"] = []
        cases["volume"] = (unmounted, self.image, b"\x89PNG\r\n\x1a\n")
        cases["digest"] = (self.container, {"RepoDigests": []}, b"\x89PNG\r\n\x1a\n")
        cases["png"] = (self.container, self.image, b"not-png")

        for name, (container, image, png) in cases.items():
            with self.subTest(name=name):
                outputs = self.outputs()
                outputs[8] = json.dumps([container])
                outputs[9] = json.dumps([image])
                persisted = []
                with self.assertRaises(ValueError):
                    self.agent.adopt_live_baseline(
                        self.Runner(outputs, png=png),
                        persisted.append,
                        lambda: "2026-07-20T10:11:12Z",
                    )
                self.assertEqual(persisted, [])

    def test_remote_identity_and_active_drift_prevent_persistence(self):
        cases = {
            "ghcr-tag": (5, "sha256:" + "d" * 64),
            "harbor": (6, "sha256:" + "d" * 64),
            "active-head": (7, "d" * 40),
        }
        for name, (index, value) in cases.items():
            with self.subTest(name=name):
                outputs = self.outputs()
                outputs[index] = value
                persisted = []
                with self.assertRaises(ValueError):
                    self.agent.adopt_live_baseline(
                        self.Runner(outputs),
                        persisted.append,
                        lambda: "2026-07-20T10:11:12Z",
                    )
                self.assertEqual(persisted, [])

    def test_invalid_timestamp_is_validated_before_persistence(self):
        persisted = []
        with self.assertRaises(ValueError):
            self.agent.adopt_live_baseline(
                self.Runner(self.outputs()),
                persisted.append,
                lambda: "not-utc",
            )
        self.assertEqual(persisted, [])

    def test_execute_once_bootstrap_projects_one_snapshot_without_runtime_mutation(self):
        runner = self.Runner(self.outputs())
        projected = []
        original_persist = self.agent.persist_snapshot

        def persist(state_path, metric_path, state):
            snapshot = original_persist(state_path, metric_path, state)
            projected.append(snapshot)
            return snapshot

        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            state_path = root / "state.json"
            metric_path = root / "kindle-release-agent.prom"
            output = io.StringIO()
            with (
                mock.patch.object(self.agent, "STATE_PATH", state_path),
                mock.patch.object(self.agent, "METRIC_PATH", metric_path),
                mock.patch.object(
                    self.agent,
                    "SubprocessRunner",
                    return_value=runner,
                ),
                mock.patch.object(
                    self.agent,
                    "persist_snapshot",
                    side_effect=persist,
                ) as project,
                mock.patch.object(
                    self.agent,
                    "reconcile_metric",
                ) as reconcile,
                mock.patch.object(self.agent.pwd, "getpwnam") as getpwnam,
                mock.patch.object(
                    self.agent,
                    "SystemOperations",
                ) as operations,
                mock.patch.object(
                    self.agent,
                    "_utc_now",
                    return_value="2026-07-20T10:11:12Z",
                ),
                contextlib.redirect_stdout(output),
            ):
                self.assertEqual(self.agent.execute_once(), 0)

            project.assert_called_once()
            reconcile.assert_not_called()
            getpwnam.assert_not_called()
            operations.assert_not_called()
            self.assertEqual(len(projected), 1)
            snapshot = projected[0]
            self.assertEqual(self.agent.load_state(state_path), snapshot)
            self.assertEqual(
                metric_path.read_text(),
                self.agent.render_prometheus(snapshot),
            )
            event = json.loads(output.getvalue())
            for field in self.agent.STATE_FIELDS:
                self.assertEqual(event[field], snapshot.to_dict()[field])

    def test_only_missing_state_bootstraps(self):
        adopted = {"phase": "succeeded"}
        with (
            mock.patch.object(self.agent, "SubprocessRunner", return_value=object()),
            mock.patch.object(
                self.agent,
                "load_state",
                side_effect=FileNotFoundError,
            ),
            mock.patch.object(
                self.agent,
                "adopt_live_baseline",
                return_value=adopted,
            ) as adopt,
            mock.patch.object(self.agent, "run_forward") as forward,
            mock.patch.object(self.agent, "reconcile_metric") as reconcile,
        ):
            self.assertEqual(self.agent.execute_once(), 0)
        adopt.assert_called_once()
        forward.assert_not_called()
        reconcile.assert_not_called()

        for error in (json.JSONDecodeError("bad", "{", 0), OSError(errno.EIO, "io")):
            with self.subTest(error=type(error).__name__):
                with (
                    mock.patch.object(
                        self.agent,
                        "load_state",
                        side_effect=error,
                    ),
                    mock.patch.object(self.agent, "adopt_live_baseline") as adopt,
                ):
                    with self.assertRaises(type(error)):
                        self.agent.execute_once()
                adopt.assert_not_called()

    def test_invalid_existing_state_never_bootstraps(self):
        state = {
            "schema": 1,
            "version": "v1.2.3",
            "digest": self.digest,
            "commit": self.commit,
            "phase": "succeeded",
            "previous": None,
            "failure": None,
            "degradation": None,
            "rollback": None,
            "updated_at": "2026-07-20T10:11:12Z",
        }
        invalid_states = {
            "json": "{",
            "missing-key": json.dumps(
                {key: value for key, value in state.items() if key != "digest"}
            ),
            "schema": json.dumps(dict(state, schema=2)),
            "version": json.dumps(dict(state, version="latest")),
            "digest": json.dumps(dict(state, digest="sha256:bad")),
            "commit": json.dumps(dict(state, commit="main")),
        }
        for name, contents in invalid_states.items():
            with self.subTest(name=name):
                with tempfile.TemporaryDirectory() as directory:
                    state_path = pathlib.Path(directory) / "state.json"
                    state_path.write_text(contents)
                    with (
                        mock.patch.object(self.agent, "STATE_PATH", state_path),
                        mock.patch.object(self.agent, "adopt_live_baseline") as adopt,
                    ):
                        with self.assertRaises(ValueError):
                            self.agent.execute_once()
                    adopt.assert_not_called()

    def test_existing_succeeded_state_is_revalidated_without_rewrite(self):
        state = {
            "schema": 1,
            "version": "v1.2.3",
            "digest": self.digest,
            "commit": self.commit,
            "phase": "succeeded",
            "previous": None,
            "failure": None,
            "degradation": None,
            "rollback": None,
            "updated_at": "2026-07-20T10:11:12Z",
        }
        with tempfile.TemporaryDirectory() as directory:
            state_path = pathlib.Path(directory) / "state.json"
            self.agent.write_state(state_path, state)
            original_bytes = state_path.read_bytes()
            original_mtime = state_path.stat().st_mtime_ns
            with (
                mock.patch.object(self.agent, "STATE_PATH", state_path),
                mock.patch.object(self.agent.pwd, "getpwnam") as getpwnam,
                mock.patch.object(self.agent, "verify_active_commit") as active,
                mock.patch.object(self.agent, "validate_runtime") as runtime,
                mock.patch.object(self.agent, "write_state") as persist,
                mock.patch.object(self.agent, "reconcile_metric") as reconcile,
                mock.patch.object(
                    self.agent, "observe_candidate", return_value=None
                ),
                mock.patch.object(self.agent, "mirror_release") as mirror,
                mock.patch.object(self.agent, "load_harbor_robot") as credentials,
            ):
                getpwnam.return_value.pw_uid = 1000
                self.assertEqual(self.agent.execute_once(), 0)
                self.assertEqual(self.agent.execute_once(), 0)
            self.assertEqual(state_path.read_bytes(), original_bytes)
            self.assertEqual(state_path.stat().st_mtime_ns, original_mtime)
        self.assertEqual(active.call_count, 2)
        self.assertEqual(runtime.call_count, 2)
        persist.assert_not_called()
        self.assertEqual(reconcile.call_count, 2)
        mirror.assert_not_called()
        credentials.assert_not_called()

    def test_existing_state_repairs_metric_before_next_runtime_mutation(self):
        state = {
            "schema": 1,
            "version": "v1.2.3",
            "digest": self.digest,
            "commit": self.commit,
            "phase": "observed",
            "previous": None,
            "failure": None,
            "degradation": None,
            "rollback": None,
            "updated_at": "2026-07-20T10:11:12Z",
        }
        stale = dict(
            state,
            version="v1.2.2",
            digest="sha256:" + "c" * 64,
            commit="d" * 40,
            updated_at="2026-07-20T09:00:00Z",
        )
        calls = []
        operations = mock.Mock()
        operations.revalidate.side_effect = (
            lambda phase, snapshot: calls.append(("revalidate", snapshot["phase"]))
        )
        operations.execute.side_effect = (
            lambda phase, snapshot: calls.append(("execute", phase))
        )
        operations.capture_previous.return_value = {
            "version": stale["version"],
            "digest": stale["digest"],
            "commit": stale["commit"],
        }

        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            state_path = root / "state.json"
            metric_path = root / "kindle-release-agent.prom"
            self.agent.write_state(state_path, state)
            self.agent.write_metric(metric_path, stale)
            original_write_metric = self.agent.write_metric

            def write_metric(path, snapshot):
                calls.append(("metric", snapshot["phase"]))
                return original_write_metric(path, snapshot)

            with (
                mock.patch.object(self.agent, "STATE_PATH", state_path),
                mock.patch.object(self.agent, "METRIC_PATH", metric_path),
                mock.patch.object(self.agent, "SubprocessRunner"),
                mock.patch.object(self.agent.pwd, "getpwnam") as getpwnam,
                mock.patch.object(
                    self.agent,
                    "SystemOperations",
                    return_value=operations,
                ),
                mock.patch.object(
                    self.agent,
                    "write_metric",
                    side_effect=write_metric,
                ),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                getpwnam.return_value.pw_uid = 1000
                self.assertEqual(self.agent.execute_once(), 0)

            self.assertEqual(
                calls[:3],
                [
                    ("revalidate", "observed"),
                    ("metric", "observed"),
                    ("execute", "verified"),
                ],
            )
            self.assertEqual(
                metric_path.read_text(),
                self.agent.render_prometheus(self.agent.load_state(state_path)),
            )

    def test_corrupt_state_fails_before_observability_or_runtime_access(self):
        corrupt_states = (
            ("{", json.JSONDecodeError),
            ('{"schema":1}\n', ValueError),
        )
        for contents, error_type in corrupt_states:
            with self.subTest(contents=contents):
                with tempfile.TemporaryDirectory() as directory:
                    root = pathlib.Path(directory)
                    state_path = root / "state.json"
                    metric_path = root / "kindle-release-agent.prom"
                    state_path.write_text(contents)
                    runner = mock.Mock()
                    output = io.StringIO()
                    with (
                        mock.patch.object(self.agent, "STATE_PATH", state_path),
                        mock.patch.object(self.agent, "METRIC_PATH", metric_path),
                        mock.patch.object(
                            self.agent,
                            "SubprocessRunner",
                            return_value=runner,
                        ),
                        mock.patch.object(self.agent.pwd, "getpwnam") as getpwnam,
                        mock.patch.object(
                            self.agent,
                            "SystemOperations",
                        ) as operations,
                        mock.patch.object(
                            self.agent,
                            "persist_snapshot",
                        ) as persist,
                        mock.patch.object(
                            self.agent,
                            "reconcile_metric",
                        ) as reconcile,
                        contextlib.redirect_stdout(output),
                    ):
                        with self.assertRaises(error_type):
                            self.agent.execute_once()

                    self.assertEqual(state_path.read_text(), contents)
                    self.assertFalse(metric_path.exists())
                    self.assertEqual(output.getvalue(), "")
                    runner.run.assert_not_called()
                    getpwnam.assert_not_called()
                    operations.assert_not_called()
                    persist.assert_not_called()
                    reconcile.assert_not_called()

    def test_projection_failure_bubbles_without_authorizing_extra_mutation(self):
        state = {
            "schema": 1,
            "version": "v1.2.3",
            "digest": self.digest,
            "commit": self.commit,
            "phase": "mirrored",
            "previous": None,
            "failure": None,
            "degradation": None,
            "rollback": None,
            "updated_at": "2026-07-20T10:11:12Z",
        }
        operations = mock.Mock()

        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            state_path = root / "state.json"
            metric_path = root / "kindle-release-agent.prom"
            self.agent.write_state(state_path, state)
            self.agent.write_metric(metric_path, state)
            previous_metric = metric_path.read_text()
            output = io.StringIO()

            with (
                mock.patch.object(self.agent, "STATE_PATH", state_path),
                mock.patch.object(self.agent, "METRIC_PATH", metric_path),
                mock.patch.object(self.agent, "SubprocessRunner"),
                mock.patch.object(self.agent.pwd, "getpwnam") as getpwnam,
                mock.patch.object(
                    self.agent,
                    "SystemOperations",
                    return_value=operations,
                ),
                mock.patch.object(
                    self.agent,
                    "write_metric",
                    side_effect=OSError("metric write failed"),
                ) as write_metric,
                contextlib.redirect_stdout(output),
            ):
                getpwnam.return_value.pw_uid = 1000
                with self.assertRaisesRegex(OSError, "metric write failed"):
                    self.agent.execute_once()

            operations.revalidate.assert_called_once()
            self.assertEqual(
                operations.execute.call_args_list,
                [mock.call("activated", mock.ANY)],
            )
            write_metric.assert_called_once()
            persisted = self.agent.load_state(state_path)
            self.assertEqual(persisted["phase"], "activated")
            event = json.loads(output.getvalue())
            self.assertEqual(event["phase"], "activated")
            self.assertEqual(metric_path.read_text(), previous_metric)

    def test_terminal_restart_repairs_only_metric_and_is_idempotent(self):
        state = {
            "schema": 1,
            "version": "v1.2.3",
            "digest": self.digest,
            "commit": self.commit,
            "phase": "succeeded",
            "previous": None,
            "failure": None,
            "degradation": None,
            "rollback": None,
            "updated_at": "2026-07-20T10:11:12Z",
        }
        previous = dict(
            state,
            version="v1.2.2",
            digest="sha256:" + "c" * 64,
            commit="d" * 40,
            updated_at="2026-07-20T09:00:00Z",
        )
        current_metric = self.agent.render_prometheus(state)
        initial_metrics = (
            None,
            current_metric[: len(current_metric) // 2],
            self.agent.render_prometheus(previous),
        )
        for initial_metric in initial_metrics:
            with self.subTest(initial_metric=initial_metric):
                with tempfile.TemporaryDirectory() as directory:
                    root = pathlib.Path(directory)
                    state_path = root / "state.json"
                    metric_path = root / "kindle-release-agent.prom"
                    self.agent.write_state(state_path, state)
                    if initial_metric is not None:
                        metric_path.write_text(initial_metric)
                    original_state = state_path.read_bytes()
                    original_mtime = state_path.stat().st_mtime_ns
                    operations = mock.Mock()
                    output = io.StringIO()
                    with (
                        mock.patch.object(self.agent, "STATE_PATH", state_path),
                        mock.patch.object(self.agent, "METRIC_PATH", metric_path),
                        mock.patch.object(self.agent, "SubprocessRunner"),
                        mock.patch.object(self.agent.pwd, "getpwnam") as getpwnam,
                        mock.patch.object(
                            self.agent,
                            "SystemOperations",
                            return_value=operations,
                        ),
                        mock.patch.object(
                            self.agent,
                            "persist_snapshot",
                        ) as persist,
                        mock.patch.object(
                            self.agent,
                            "observe_candidate",
                            return_value=None,
                        ),
                        contextlib.redirect_stdout(output),
                    ):
                        getpwnam.return_value.pw_uid = 1000
                        self.assertEqual(self.agent.execute_once(), 0)
                        repaired_mtime = metric_path.stat().st_mtime_ns
                        with mock.patch.object(
                            self.agent,
                            "write_metric",
                            wraps=self.agent.write_metric,
                        ) as metric_write:
                            self.assertEqual(self.agent.execute_once(), 0)
                        metric_write.assert_not_called()

                    self.assertEqual(state_path.read_bytes(), original_state)
                    self.assertEqual(state_path.stat().st_mtime_ns, original_mtime)
                    self.assertEqual(
                        metric_path.read_text(),
                        self.agent.render_prometheus(state),
                    )
                    self.assertEqual(metric_path.stat().st_mtime_ns, repaired_mtime)
                    self.assertEqual(output.getvalue(), "")
                    self.assertEqual(operations.revalidate.call_count, 2)
                    operations.execute.assert_not_called()
                    persist.assert_not_called()


class ReleasePollingContract(unittest.TestCase):
    def setUp(self):
        self.agent = load_agent()
        self.current = self.agent.validate_state(
            {
                "schema": 1,
                "version": "v1.2.3",
                "digest": "sha256:" + "a" * 64,
                "commit": "b" * 40,
                "phase": "succeeded",
                "previous": None,
                "failure": None,
                "degradation": "external-reporting-unavailable",
                "rollback": None,
                "updated_at": "2026-07-20T10:11:12Z",
            }
        )

    def test_no_new_commit_only_revalidates_current_release(self):
        operations = mock.Mock()
        persist = mock.Mock()
        reconcile = mock.Mock()
        with mock.patch.object(
            self.agent,
            "observe_candidate",
            return_value=None,
        ):
            result = self.agent.poll_release(
                self.current,
                operations,
                persist,
                lambda: "2026-07-20T11:00:00Z",
                reconcile,
            )
        self.assertIs(result, self.current)
        operations.revalidate.assert_called_once_with("succeeded", self.current)
        operations.execute.assert_not_called()
        persist.assert_not_called()
        reconcile.assert_called_once_with(self.current)

    def test_new_commit_persists_observed_state_then_runs_forward(self):
        candidate = {
            "version": "v1.2.4",
            "digest": "sha256:" + "c" * 64,
            "commit": "d" * 40,
        }
        operations = mock.Mock()
        persist = mock.Mock()
        reconcile = mock.Mock()
        terminal = dict(self.current, **candidate)
        with (
            mock.patch.object(
                self.agent,
                "observe_candidate",
                return_value=candidate,
            ),
            mock.patch.object(
                self.agent,
                "run_forward",
                return_value=terminal,
            ) as forward,
        ):
            result = self.agent.poll_release(
                self.current,
                operations,
                persist,
                lambda: "2026-07-20T11:00:00Z",
                reconcile,
            )
        observed = persist.call_args.args[0]
        self.assertEqual(observed["phase"], "observed")
        self.assertEqual(observed["previous"]["commit"], self.current["commit"])
        self.assertIsNone(observed["degradation"])
        forward.assert_called_once_with(
            observed,
            operations,
            persist,
            mock.ANY,
            after_revalidate=reconcile,
        )
        self.assertIs(result, terminal)

    def test_failed_attempt_quarantines_candidate_until_origin_advances(self):
        failed = self.agent.validate_state(
            dict(
                self.current,
                version="v1.2.4",
                digest="sha256:" + "c" * 64,
                commit="d" * 40,
                phase="failed",
                previous={
                    "version": self.current["version"],
                    "digest": self.current["digest"],
                    "commit": self.current["commit"],
                },
                failure="controlled post-recreate failure",
                rollback="failed",
            )
        )
        operations = mock.Mock()
        persist = mock.Mock()
        with mock.patch.object(self.agent, "poll_release") as poll:
            result = self.agent.recover_failed_attempt(
                failed,
                operations,
                persist,
                lambda: "2026-07-20T11:00:00Z",
                mock.Mock(),
            )
        operations.revalidate.assert_called_once_with("failed", failed)
        recovered = persist.call_args_list[-1].args[0]
        self.assertEqual(recovered["commit"], self.current["commit"])
        self.assertEqual(recovered["phase"], "succeeded")
        self.assertIsNone(recovered["previous"])
        poll.assert_not_called()
        self.assertEqual(result, recovered)


class ReportingOrchestrationContract(unittest.TestCase):
    def setUp(self):
        self.agent = load_agent()
        self.state = {
            "schema": 1,
            "version": "v1.2.3",
            "digest": "sha256:" + "a" * 64,
            "commit": "b" * 40,
            "phase": "succeeded",
            "previous": {
                "version": "v1.2.2",
                "digest": "sha256:" + "c" * 64,
                "commit": "d" * 40,
            },
            "failure": None,
            "degradation": None,
            "rollback": None,
            "updated_at": "2026-07-20T12:00:00Z",
        }

    def snapshot(self, **updates):
        state = dict(self.state)
        state.update(updates)
        return self.agent.validate_state(state)

    def test_execute_once_reports_each_terminal_path_after_local_projection(self):
        fixtures = (
            ("bootstrap", self.snapshot(previous=None), 0),
            ("revalidated", self.snapshot(), 0),
            ("forward", self.snapshot(), 0),
            (
                "rollback",
                self.snapshot(
                    phase="failed",
                    failure="runtime failed",
                    rollback="rollback-ok",
                ),
                1,
            ),
        )
        for case, terminal, expected_return in fixtures:
            with self.subTest(case=case):
                events = []
                reporter = mock.Mock()
                reporter.deliver.side_effect = lambda value: events.append(
                    ("report", value)
                )
                persist_snapshot = mock.Mock(
                    side_effect=lambda _state_path, _metric_path, value: events.append(
                        ("local", value)
                    )
                )
                reconcile_metric = mock.Mock(
                    side_effect=lambda _path, value: events.append(("local", value))
                )

                def adopt(_runner, persist, _now):
                    persist(terminal)
                    return terminal

                def forward(_state, _operations, persist, _now, after_revalidate):
                    if case == "revalidated":
                        after_revalidate(terminal)
                    else:
                        persist(terminal)
                    return terminal

                load = (
                    mock.Mock(side_effect=FileNotFoundError())
                    if case == "bootstrap"
                    else mock.Mock(return_value=self.snapshot(phase="observed"))
                )
                with (
                    mock.patch.object(self.agent, "load_state", load),
                    mock.patch.object(
                        self.agent,
                        "adopt_live_baseline",
                        side_effect=adopt,
                    ),
                    mock.patch.object(self.agent, "run_forward", side_effect=forward),
                    mock.patch.object(self.agent, "persist_snapshot", persist_snapshot),
                    mock.patch.object(self.agent, "reconcile_metric", reconcile_metric),
                    mock.patch.object(
                        self.agent,
                        "ExternalReporter",
                        return_value=reporter,
                    ),
                    mock.patch.object(self.agent, "SubprocessRunner"),
                    mock.patch.object(self.agent, "SystemOperations"),
                    mock.patch.object(self.agent.pwd, "getpwnam") as getpwnam,
                ):
                    getpwnam.return_value.pw_uid = 1000
                    self.assertEqual(self.agent.execute_once(), expected_return)

                self.assertEqual(events, [("local", terminal), ("report", terminal)])
                reporter.deliver.assert_called_once_with(terminal)

    def test_external_failures_persist_one_sanitized_local_degradation(self):
        sentinel = "credential-secret-sentinel"
        failures = (
            self.agent.ExternalCredentialError(sentinel),
            self.agent.ExternalSigningError(sentinel),
            self.agent.ExternalHttpError(sentinel),
            self.agent.ExternalReportingError(sentinel),
        )
        for phase, failure, expected_return in (
            ("succeeded", None, 0),
            ("failed", "runtime failed", 1),
        ):
            terminal = self.snapshot(
                phase=phase,
                failure=failure,
                rollback="rollback-ok" if phase == "failed" else None,
            )
            for external_failure in failures:
                with self.subTest(phase=phase, error=type(external_failure).__name__):
                    reporter = mock.Mock()
                    reporter.deliver.side_effect = external_failure
                    persist = mock.Mock()
                    degraded = self.agent.report_terminal(
                        terminal,
                        reporter,
                        persist,
                        lambda: "2026-07-20T12:01:00Z",
                    )
                    self.assertEqual(
                        degraded["degradation"],
                        "external-reporting-unavailable",
                    )
                    self.assertEqual(degraded["updated_at"], "2026-07-20T12:01:00Z")
                    for field in self.agent.STATE_FIELDS:
                        if field not in {"degradation", "updated_at"}:
                            self.assertEqual(degraded[field], terminal[field])
                    self.assertEqual(1 if degraded["phase"] == "failed" else 0, expected_return)
                    reporter.deliver.assert_called_once_with(terminal)
                    persist.assert_called_once_with(degraded)
                    self.assertNotIn(sentinel, json.dumps(degraded.to_dict()))

    def test_successful_retry_clears_reporting_degradation_atomically(self):
        degraded = self.snapshot(degradation="external-reporting-unavailable")
        reporter = mock.Mock()
        persist = mock.Mock()
        recovered = self.agent.report_terminal(
            degraded,
            reporter,
            persist,
            lambda: "2026-07-20T12:02:00Z",
        )
        self.assertIsNone(recovered["degradation"])
        self.assertEqual(recovered["updated_at"], "2026-07-20T12:02:00Z")
        reporter.deliver.assert_called_once_with(recovered)
        persist.assert_called_once_with(recovered)

    def test_local_projection_failure_propagates_without_reporting_recursion(self):
        terminal = self.snapshot()
        reporter = mock.Mock()
        reporter.deliver.side_effect = self.agent.ExternalHttpError(
            "provider-secret-sentinel"
        )
        persist = mock.Mock(side_effect=OSError("atomic writer failed"))
        with self.assertRaisesRegex(OSError, "atomic writer failed"):
            self.agent.report_terminal(
                terminal,
                reporter,
                persist,
                lambda: "2026-07-20T12:01:00Z",
            )
        reporter.deliver.assert_called_once_with(terminal)
        persist.assert_called_once()

    def test_unexpected_reporter_bug_is_not_misclassified_as_delivery_failure(self):
        terminal = self.snapshot()
        reporter = mock.Mock()
        reporter.deliver.side_effect = RuntimeError("programming error")
        persist = mock.Mock()
        with self.assertRaisesRegex(RuntimeError, "programming error"):
            self.agent.report_terminal(
                terminal,
                reporter,
                persist,
                lambda: "2026-07-20T12:01:00Z",
            )
        persist.assert_not_called()

    def test_reporting_authority_constants_ignore_hostile_environment(self):
        hostile = {
            "GITHUB_APP_CONFIG": "/tmp/attacker.json",
            "GITHUB_APP_KEY": "/tmp/attacker.pem",
            "DISCORD_DEPLOYS_WEBHOOK": "https://evil.invalid/deploys",
            "DISCORD_INCIDENTS_WEBHOOK": "https://evil.invalid/incidents",
            "GITHUB_API_HOST": "evil.invalid",
            "GITHUB_REPOSITORY": "attacker/repo",
        }
        with mock.patch.dict(os.environ, hostile, clear=True):
            self.assertEqual(
                self.agent.GITHUB_APP_CONFIG,
                pathlib.Path("/run/vault-agent/kindle-release-github-app.json"),
            )
            self.assertEqual(
                self.agent.GITHUB_APP_KEY,
                pathlib.Path("/run/vault-agent/kindle-release-github-app.pem"),
            )
            self.assertEqual(
                self.agent.DISCORD_DEPLOYS_WEBHOOK,
                pathlib.Path("/run/vault-agent/kindle-release-discord-deploys"),
            )
            self.assertEqual(
                self.agent.DISCORD_INCIDENTS_WEBHOOK,
                pathlib.Path("/run/vault-agent/kindle-release-discord-incidents"),
            )
            self.assertEqual(self.agent.GITHUB_API_HOST, "api.github.com")
            self.assertEqual(self.agent.GITHUB_REPOSITORY_OWNER, "ErikBPF")
            self.assertEqual(self.agent.GITHUB_REPOSITORY, "servarr")


class EntrypointContract(unittest.TestCase):
    def setUp(self):
        self.agent = load_agent()
        self.reporter_factory = mock.patch.object(
            self.agent,
            "ExternalReporter",
        ).start()
        self.report_terminal = mock.patch.object(
            self.agent,
            "report_terminal",
            side_effect=lambda result, *_args: result,
        ).start()
        self.addCleanup(mock.patch.stopall)

    def test_main_has_no_arguments_and_rejects_unexpected_input(self):
        self.assertEqual(tuple(inspect.signature(self.agent.main).parameters), ())
        with self.assertRaises(TypeError):
            self.agent.main("unexpected")

    def test_production_authority_is_fixed_and_ignores_hostile_environment(self):
        hostile = {
            "STATE_PATH": "/tmp/attacker-state.json",
            "LOCK_PATH": "/tmp/attacker.lock",
            "HARBOR_ENV": "/tmp/attacker.env",
            "DEPLOY_USER": "root",
        }
        with mock.patch.dict(os.environ, hostile, clear=True):
            self.assertEqual(
                self.agent.STATE_PATH,
                pathlib.Path("/var/lib/kindle-release-agent/state.json"),
            )
            self.assertEqual(
                self.agent.LOCK_PATH,
                pathlib.Path("/run/kindle-release-agent/lock"),
            )
            self.assertEqual(
                self.agent.HARBOR_ENV,
                pathlib.Path("/run/vault-agent/harbor.env"),
            )
            self.assertEqual(
                self.agent.METRIC_PATH,
                pathlib.Path(
                    "/var/lib/node-exporter-textfile/kindle-release-agent.prom"
                ),
            )
            self.assertEqual(self.agent.DEPLOY_USER, "erik")

    def test_execute_once_wires_fixed_state_user_operations_and_utc_clock(self):
        state = {"phase": "observed"}
        runner_instance = object()
        operations_instance = object()
        written = {"phase": "succeeded"}

        def run_forward(current, operations, persist, now, after_revalidate):
            self.assertIs(current, state)
            self.assertIs(operations, operations_instance)
            after_revalidate(current)
            persist(written)
            self.assertEqual(now(), "2026-07-20T10:11:12Z")
            return written

        with (
            mock.patch.object(
                self.agent,
                "SubprocessRunner",
                return_value=runner_instance,
            ) as runner,
            mock.patch.object(self.agent.pwd, "getpwnam") as getpwnam,
            mock.patch.object(
                self.agent,
                "SystemOperations",
                return_value=operations_instance,
            ) as operations,
            mock.patch.object(
                self.agent,
                "load_state",
                return_value=state,
            ) as load,
            mock.patch.object(self.agent, "persist_snapshot") as persist,
            mock.patch.object(self.agent, "reconcile_metric") as reconcile,
            mock.patch.object(
                self.agent,
                "_utc_now",
                return_value="2026-07-20T10:11:12Z",
            ),
            mock.patch.object(
                self.agent,
                "run_forward",
                side_effect=run_forward,
            ) as forward,
        ):
            getpwnam.return_value.pw_uid = 1000
            self.assertEqual(self.agent.execute_once(), 0)

        runner.assert_called_once_with()
        getpwnam.assert_called_once_with("erik")
        operations.assert_called_once_with(
            runner_instance,
            1000,
            pathlib.Path("/run/vault-agent/harbor.env"),
        )
        load.assert_called_once_with(
            pathlib.Path("/var/lib/kindle-release-agent/state.json")
        )
        forward.assert_called_once()
        persist.assert_called_once_with(
            pathlib.Path("/var/lib/kindle-release-agent/state.json"),
            pathlib.Path(
                "/var/lib/node-exporter-textfile/kindle-release-agent.prom"
            ),
            written,
        )
        reconcile.assert_called_once_with(
            pathlib.Path(
                "/var/lib/node-exporter-textfile/kindle-release-agent.prom"
            ),
            state,
        )

    def test_execute_once_projects_every_persisted_transition_once(self):
        state = {
            "schema": 1,
            "version": "v1.2.3",
            "digest": "sha256:" + "a" * 64,
            "commit": "b" * 40,
            "phase": "observed",
            "previous": None,
            "failure": None,
            "degradation": None,
            "rollback": None,
            "updated_at": "2026-07-20T10:11:12Z",
        }
        verified = self.agent.transition(state, "verified", "2026-07-20T10:12:00Z")
        mirrored = self.agent.transition(
            verified,
            "mirrored",
            "2026-07-20T10:13:00Z",
        )

        def run_forward(current, operations, persist, now, after_revalidate):
            after_revalidate(current)
            persist(verified)
            persist(mirrored)
            return mirrored

        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            state_path = root / "state.json"
            metric_path = root / "kindle-release-agent.prom"
            self.agent.write_state(state_path, state)
            output = io.StringIO()
            with (
                mock.patch.object(self.agent, "STATE_PATH", state_path),
                mock.patch.object(self.agent, "METRIC_PATH", metric_path),
                mock.patch.object(self.agent, "SubprocessRunner"),
                mock.patch.object(self.agent.pwd, "getpwnam") as getpwnam,
                mock.patch.object(self.agent, "SystemOperations"),
                mock.patch.object(
                    self.agent,
                    "run_forward",
                    side_effect=run_forward,
                ),
                contextlib.redirect_stdout(output),
            ):
                getpwnam.return_value.pw_uid = 1000
                self.assertEqual(self.agent.execute_once(), 0)

            events = [json.loads(line) for line in output.getvalue().splitlines()]
            self.assertEqual(len(events), 2)
            for event, expected in zip(events, (verified, mirrored)):
                self.assertEqual(event["event"], "kindle-release-agent-snapshot")
                for field in self.agent.STATE_FIELDS:
                    self.assertEqual(event[field], expected.to_dict()[field])
            self.assertEqual(self.agent.load_state(state_path), mirrored)
            self.assertEqual(
                metric_path.read_text(),
                self.agent.render_prometheus(mirrored),
            )

    def test_main_holds_real_nonblocking_lock_until_execute_once_returns(self):
        with tempfile.TemporaryDirectory() as directory:
            lock_path = pathlib.Path(directory) / "agent.lock"
            observations = []

            def execute_once():
                contender = os.open(lock_path, os.O_RDWR)
                try:
                    with self.assertRaises(BlockingIOError):
                        fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    observations.append("locked")
                finally:
                    os.close(contender)
                return 0

            with (
                mock.patch.object(self.agent, "LOCK_PATH", lock_path),
                mock.patch.object(
                    self.agent,
                    "execute_once",
                    side_effect=execute_once,
                ) as execute,
            ):
                self.assertEqual(self.agent.main(), 0)
            execute.assert_called_once_with()
            self.assertEqual(observations, ["locked"])

            contender = os.open(lock_path, os.O_RDWR)
            try:
                fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
            finally:
                os.close(contender)

    def test_contention_skips_with_one_fixed_event_and_no_shared_state_access(self):
        with tempfile.TemporaryDirectory() as directory:
            lock_path = pathlib.Path(directory) / "agent.lock"
            owner = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
            fcntl.flock(owner, fcntl.LOCK_EX | fcntl.LOCK_NB)
            output = io.StringIO()
            try:
                with (
                    mock.patch.object(self.agent, "LOCK_PATH", lock_path),
                    mock.patch.object(self.agent, "execute_once") as execute,
                    mock.patch.object(self.agent, "load_state") as load,
                    mock.patch.object(self.agent, "write_state") as persist,
                    mock.patch.object(self.agent, "write_metric") as metric,
                    mock.patch.object(self.agent, "persist_snapshot") as project,
                    mock.patch.object(self.agent, "reconcile_metric") as reconcile,
                    mock.patch.object(self.agent, "SystemOperations") as operations,
                    mock.patch.object(self.agent, "SubprocessRunner") as runner,
                    contextlib.redirect_stdout(output),
                ):
                    self.assertEqual(self.agent.main(), 0)
            finally:
                os.close(owner)

        self.assertEqual(output.getvalue(), '{"event":"lock-busy"}\n')
        execute.assert_not_called()
        load.assert_not_called()
        persist.assert_not_called()
        metric.assert_not_called()
        project.assert_not_called()
        reconcile.assert_not_called()
        operations.assert_not_called()
        runner.assert_not_called()

    def test_non_contention_lock_error_propagates_without_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            lock_path = pathlib.Path(directory) / "agent.lock"
            with (
                mock.patch.object(self.agent, "LOCK_PATH", lock_path),
                mock.patch.object(
                    self.agent.fcntl,
                    "flock",
                    side_effect=OSError(errno.EPERM, "not permitted"),
                ),
                mock.patch.object(self.agent, "execute_once") as execute,
            ):
                with self.assertRaises(OSError) as raised:
                    self.agent.main()
        self.assertEqual(raised.exception.errno, errno.EPERM)
        execute.assert_not_called()

    def test_lock_file_open_error_is_not_classified_as_contention(self):
        with (
            mock.patch.object(
                self.agent.os,
                "open",
                side_effect=OSError(errno.EACCES, "permission denied"),
            ),
            mock.patch.object(self.agent, "execute_once") as execute,
        ):
            with self.assertRaises(OSError) as raised:
                self.agent.main()
        self.assertEqual(raised.exception.errno, errno.EACCES)
        execute.assert_not_called()


class NixModuleContract(unittest.TestCase):
    def test_reporting_provision_adds_dedicated_policy_without_replacing_shared(self):
        source = JUSTFILE_PATH.read_text()
        recipe = source.split("provision-kindle-release-reporting:", 1)[1].split(
            "diagnose-kindle-claude-usage:", 1
        )[0]
        self.assertIn("sys/policies/acl/kindle-release-read", recipe)
        self.assertIn("auth/approle/role/vault-agent", recipe)
        self.assertIn("token_policies", recipe)
        self.assertNotIn("sys/policies/acl/discord-read", recipe)
        self.assertNotIn('role_payload="$(jq -c \'', recipe)

    def test_reporting_provision_recipe_has_valid_shell_syntax(self):
        rendered = subprocess.run(
            ["just", "--dry-run", "provision-kindle-release-reporting"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        checked = subprocess.run(
            ["bash", "-n"],
            input=rendered,
            capture_output=True,
            text=True,
        )
        self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_module_declares_fixed_oneshot_and_disabled_timer(self):
        source = MODULE_PATH.read_text()
        required = (
            "flake.modules.nixos.discovery-kindle-release-agent",
            "options.services.kindleReleaseAgent",
            "enable = lib.mkEnableOption",
            "timerEnable = lib.mkEnableOption",
            'Type = "oneshot"',
            'OnCalendar = "hourly"',
            "Persistent = true",
            "ProtectSystem = \"strict\"",
            "ProtectHome = \"read-only\"",
            "NoNewPrivileges = true",
            "PrivateTmp = true",
            "ReadWritePaths",
            "RuntimeDirectory = \"kindle-release-agent\"",
            "/run/kindle-release-agent",
            "/var/lib/kindle-release-agent",
            "/var/lib/node-exporter-textfile",
            "/home/erik/servarr",
            "docker.service",
            "bash",
            "kindle-release-agent-failure-drill",
            'substituteInPlace "$out"',
            "openssh",
            "vault-agent.service",
        )
        for contract in required:
            with self.subTest(contract=contract):
                self.assertIn(contract, source)
        self.assertNotIn('wantedBy = ["timers.target"]', source)

    def test_discovery_imports_agent_with_timer_enabled(self):
        source = (
            ROOT / "modules/hosts/discovery/default.nix"
        ).read_text()
        self.assertIn("m.nixos.discovery-kindle-release-agent", source)
        self.assertIn("services.kindleReleaseAgent = {", source)
        self.assertIn("enable = true", source)
        self.assertIn("timerEnable = true", source)

    def test_vault_agent_renders_dedicated_root_only_reporting_secrets(self):
        source = (ROOT / "modules/hosts/discovery/vault.nix").read_text()
        for path in (
            "/run/vault-agent/kindle-release-github-app.json",
            "/run/vault-agent/kindle-release-github-app.pem",
            "/run/vault-agent/kindle-release-discord-deploys",
            "/run/vault-agent/kindle-release-discord-incidents",
        ):
            with self.subTest(path=path):
                self.assertIn(f'destination = "{path}"', source)
        self.assertGreaterEqual(source.count('perms = "0600"'), 4)


if __name__ == "__main__":
    unittest.main()
