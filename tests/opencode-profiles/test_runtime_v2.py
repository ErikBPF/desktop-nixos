"""Native V2 API/hook smoke in an isolated, credential-free loopback server."""
import base64
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import unittest
import urllib.error
import urllib.request

from test_settings import ROOT


class NativeRuntime(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = os.environ.get("OPENCODE_TEST_BINARY", "opencode")
        version = subprocess.check_output([cls.binary, "--version"], text=True).strip()
        if not version.startswith("opencode v2."):
            raise AssertionError("Native V2 binary required")
        print("Runtime smoke:", version, flush=True)
        home = json.loads(subprocess.check_output([
            "nix", "eval", "--json",
            ".#nixosConfigurations.endeavour.config.home-manager.users.erik",
            "--apply", '''home: {
              settings = home.programs.opencode.settings;
              cli = home.xdg.configFile."opencode/cli.json".text;
            }''',
        ], cwd=ROOT, text=True))
        settings = home["settings"]
        ponytail = next(p for p in settings["plugins"] if "opencode-ponytail-v2-0.1.0" in p)
        if not Path(ponytail).is_dir():
            raise AssertionError("Realize the managed Ponytail derivation before runtime checks")
        temporary_parent = Path.home() / ".local/share/opencode-v2/tmp/opencode"
        temporary_parent.mkdir(parents=True, exist_ok=True)
        cls.temporary = tempfile.TemporaryDirectory(dir=temporary_parent)
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        config = cls.root / "config/opencode"
        config.mkdir(parents=True)
        cls.repo = cls.root / "repo"
        cls.repo.mkdir()
        (cls.repo / "opencode.json").write_text((ROOT / "opencode.json").read_text())
        # No provider credential substitutions, real model endpoint, or MCP startup.
        (config / "opencode.json").write_text(json.dumps({
            "update": settings["update"], "compaction": settings["compaction"],
            "plugins": settings["plugins"], "permissions": settings["permissions"],
            "experimental": {"policies": [
                {"action": "provider.use", "resource": "*", "effect": "deny"},
                 *[p for p in settings["experimental"]["policies"] if p["action"] == "tool.use"],
            ]},
            "agent": {"probe": {"mode": "primary", "permission": {"read": "allow"}}},
        }))
        (config / "cli.json").write_text(home["cli"])
        env = {"PATH": os.environ["PATH"], "HOME": str(cls.root)}
        env.update({f"XDG_{s}_HOME": str(cls.root / s.lower()) for s in ["CONFIG", "DATA", "CACHE", "STATE"]})
        env.update(OPENCODE_DISABLE_CLAUDE_CODE="1", OPENCODE_DISABLE_MODELS_FETCH="1",
                    OPENCODE_PASSWORD="synthetic-loopback")
        # Match the backend's inline routing layer: it must retain global
        # tool.use denials while appending its provider policies.
        env["OPENCODE_CONFIG_CONTENT"] = json.dumps({"experimental": {"policies": [
            {"action": "provider.use", "resource": "*", "effect": "deny"},
            {"action": "provider.use", "resource": "work", "effect": "allow"},
            {"action": "provider.use", "resource": "opencode-go", "effect": "allow"},
            {"action": "provider.use", "resource": "openai", "effect": "allow"},
        ]}})
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        cls.url = f"http://127.0.0.1:{port}"
        cls.log = (cls.root / "server.log").open("w")
        cls.addClassCleanup(cls.log.close)
        cls.server = subprocess.Popen([
            cls.binary, "serve", "--hostname", "127.0.0.1", "--port", str(port),
        ], cwd=cls.repo, env=env, stdout=cls.log, stderr=cls.log)
        cls.addClassCleanup(cls.stop_server)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            try:
                cls.request("/openapi.json")
                break
            except (urllib.error.URLError, TimeoutError):
                if cls.server.poll() is not None:
                    raise AssertionError("Disposable server exited before readiness")
                time.sleep(0.1)
        else:
            raise AssertionError("Disposable server readiness deadline exceeded")
        # HTTP readiness precedes asynchronous plugin and agent registration.
        deadline = time.monotonic() + 30
        while True:
            plugins = cls.request("/api/plugin?location[directory]=" + str(cls.repo))["data"]
            agents = cls.request("/api/agent?location[directory]=" + str(cls.repo))["data"]
            active = {p.get("id") for p in plugins if p["state"]["status"] == "active"}
            if {"rtk", "homelab-gateway-headers", "ponytail"} <= active and any(
                    agent.get("id") == "probe" for agent in agents):
                break
            if time.monotonic() >= deadline:
                states = {p.get("id", p.get("package")): p["state"] for p in plugins}
                raise AssertionError(f"Plugins/agent not ready: {states!r}; agents={[a.get('id') for a in agents]!r}")
            time.sleep(0.1)
        cls.session = cls.request("/api/session", {"agent": "probe", "title": "Synthetic permissions",
            "location": {"directory": str(cls.repo)}})["data"]["id"]

    @classmethod
    def stop_server(cls):
        cls.server.terminate()
        try:
            cls.server.wait(timeout=10)
        except subprocess.TimeoutExpired:
            cls.server.kill()
            cls.server.wait()

    @classmethod
    def request(cls, path, body=None):
        headers = {"Authorization": "Basic " + base64.b64encode(b"opencode:synthetic-loopback").decode()}
        if body is not None:
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(cls.url + path, headers=headers,
                                         data=None if body is None else json.dumps(body).encode())
        with urllib.request.urlopen(request, timeout=10) as response:
            content = response.read()
            return json.loads(content) if content else None

    def permission(self, action, resource):
        return self.request(f"/api/session/{self.session}/permission", {
            "action": action, "resources": [resource], "agent": "probe",
        })["data"]["effect"]

    def test_native_plugins_and_ponytail_commands_loaded(self):
        plugins = self.request("/api/plugin?location[directory]=" + str(self.repo))["data"]
        active = {p.get("id"): p["state"]["status"] for p in plugins}
        for name in ["rtk", "homelab-gateway-headers", "ponytail"]:
            self.assertEqual(active.get(name), "active", plugins)
        commands = self.request("/api/command?location[directory]=" + str(self.repo))["data"]
        self.assertTrue(any(command["name"] == "ponytail" for command in commands))

    def test_global_policy_blocks_agent_read_override(self):
        for path in ["local.secrets.json", "nested/local.secret.json", ".env", "nested/.env.local",
                     ".ssh/id_rsa", "/home/erik/.ssh/id_ed25519",
                     "/home/erik/.config/sops/age/keys.txt", "/run/secrets/opencode/work_key"]:
            with self.subTest(path=path):
                self.assertEqual(self.permission("read", path), "deny")
        self.assertEqual(self.permission("read", "README.md"), "allow")

    def test_shell_ask_and_authorized_deploy_not_denied(self):
        for command in ["cat .env", "git status; cat .env", "git status && cat .env",
                        "rtk git status && cat .env", "git diff --no-index /dev/null .env",
                        "just home-switch", "just switch endeavour"]:
            with self.subTest(command=command):
                self.assertEqual(self.permission("shell", command), "ask")
        self.assertEqual(self.permission("shell", "git status --short"), "allow")
        self.assertEqual(self.permission("shell", "docker volume rm db"), "deny")


if __name__ == "__main__":
    unittest.main()
