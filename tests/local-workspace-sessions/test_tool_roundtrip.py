"""Native standalone model -> RTK shell tool -> model, with no real provider."""
import http.server
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUCCESS = "SYNTHETIC_NATIVE_TOOL_ROUNDTRIP_OK"
COMMAND = "git status --short"
MARKER = "tool-roundtrip-marker.txt"


class ToolRoundtrip(unittest.TestCase):
    def test_model_receives_native_rtk_shell_result_and_continues(self):
        managed = json.loads(subprocess.check_output([
            "nix", "eval", "--json", ".#nixosConfigurations.endeavour.config.home-manager.users.erik",
            "--apply", '''h: {
              binary = "${h.programs.opencode.package}/bin/opencode";
              plugins = h.programs.opencode.settings.plugins;
              rtk = map (p: "${p}/bin/rtk")
                (builtins.filter (p: (p.pname or "") == "rtk") h.home.packages);
            }''',
        ], cwd=ROOT, text=True))
        binary = os.environ.get("OPENCODE_TEST_BINARY", managed["binary"])
        plugins = [p for p in managed["plugins"] if p.startswith("file://") and p.endswith("-rtk")]
        self.assertEqual(len(plugins), 1, "expected one evaluated managed native RTK plugin")
        self.assertEqual(len(managed["rtk"]), 1, "expected one exact managed RTK binary")
        self.assertTrue(Path(binary).is_file(), "realize the V2 package before this smoke")
        self.assertTrue(Path(managed["rtk"][0]).is_file(), "realize managed RTK before this smoke")
        requests, protocol_errors, tool_results = [], [], []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                requests.append(body)
                tools = [t["function"] for t in body.get("tools", []) if t.get("type") == "function"]
                shell = next((t for t in tools if t["name"] == "shell"), None)
                results = [m for m in body.get("messages", [])
                           if m.get("role") == "tool" and m.get("tool_call_id") == "call_native_status"]
                tool_results.extend(results)
                if self.path != "/v1/chat/completions" or shell is None:
                    protocol_errors.append({"path": self.path, "tools": [t["name"] for t in tools]})
                    message = {"role": "assistant", "content": "SYNTHETIC_PROTOCOL_ERROR"}
                    finish = "stop"
                elif results:
                    output = json.dumps(results)
                    if MARKER not in output:
                        protocol_errors.append({"tool_result": output})
                    message = {"role": "assistant", "content": SUCCESS if MARKER in output else "SYNTHETIC_TOOL_FAILED"}
                    finish = "stop"
                elif len(requests) == 1:
                    message = {"role": "assistant", "content": None, "tool_calls": [{
                        "id": "call_native_status", "type": "function",
                        "function": {"name": shell["name"], "arguments": json.dumps({"command": COMMAND})},
                    }]}
                    finish = "tool_calls"
                else:
                    protocol_errors.append({"missing_continuation_result": True})
                    message = {"role": "assistant", "content": "SYNTHETIC_TOOL_FAILED"}
                    finish = "stop"
                base = {"id": "synthetic-roundtrip", "created": 1, "model": "synthetic"}
                usage = {"prompt_tokens": 100, "completion_tokens": 20, "total_tokens": 120}
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream" if body.get("stream") else "application/json")
                self.end_headers()
                if body.get("stream"):
                    delta = dict(message)
                    if "tool_calls" in delta:
                        delta["tool_calls"] = [{"index": 0, **delta["tool_calls"][0]}]
                    for chunk in (
                        {**base, "object": "chat.completion.chunk", "choices": [{"index": 0, "delta": delta, "finish_reason": None}]},
                        {**base, "object": "chat.completion.chunk", "choices": [{"index": 0, "delta": {}, "finish_reason": finish}], "usage": usage},
                    ):
                        self.wfile.write(("data: " + json.dumps(chunk) + "\n\n").encode())
                    self.wfile.write(b"data: [DONE]\n\n")
                else:
                    self.wfile.write(json.dumps({**base, "object": "chat.completion", "usage": usage,
                        "choices": [{"index": 0, "message": message, "finish_reason": finish}]}).encode())

            def log_message(self, *_args):
                pass

        approved = Path.home() / ".local/share/opencode-v2/tmp/opencode"
        temporary_parent = os.environ.get("OPENCODE_TEST_TMPDIR") or (str(approved) if approved.is_dir() else None)
        with tempfile.TemporaryDirectory(prefix="native-tool-roundtrip-", dir=temporary_parent) as temporary, \
                http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            root = Path(temporary)
            repo = root / "repo"
            repo.mkdir()
            (repo / MARKER).write_text("Synthetic untracked file, never committed.\n")
            config = root / "config/opencode"
            config.mkdir(parents=True)
            binaries = root / "bin"
            binaries.mkdir()
            trace = root / "rtk-trace.jsonl"
            # Trace real RTK, not a mocked tool result or plugin hook.
            tracer = binaries / "rtk"
            tracer.write_text(f'''#!{shutil.which("python3")}
import json, os, sys
with open({str(trace)!r}, "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
os.execv({managed["rtk"][0]!r}, [{managed["rtk"][0]!r}, *sys.argv[1:]])
''')
            tracer.chmod(0o700)
            settings = {
                "model": "synthetic/synthetic", "plugins": plugins, "update": "disable",
                "shell": shutil.which("bash"),
                "permissions": [
                    {"action": "shell", "resource": "*", "effect": "deny"},
                    {"action": "shell", "resource": COMMAND, "effect": "allow"},
                ],
                "providers": {"synthetic": {
                    "package": "@opencode/ai/providers/openai-compatible",
                    "settings": {"baseURL": f"http://127.0.0.1:{server.server_port}/v1", "apiKey": "synthetic-no-secret"},
                    "models": {"synthetic": {"name": "Synthetic", "limit": {"context": 100000, "output": 1000}}},
                }},
            }
            (config / "opencode.json").write_text(json.dumps(settings))
            env = {
                "PATH": str(binaries) + os.pathsep + os.environ["PATH"],
                "HOME": str(root / "home"), "OPENCODE_TEST_HOME": str(root / "home"),
                "XDG_CONFIG_HOME": str(root / "config"), "XDG_DATA_HOME": str(root / "data"),
                "XDG_CACHE_HOME": str(root / "cache"), "XDG_STATE_HOME": str(root / "state"),
                "TMPDIR": str(root / "tmp"), "SHELL": shutil.which("bash"),
                "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                "OPENCODE_DISABLE_CLAUDE_CODE": "1", "OPENCODE_DISABLE_MODELS_FETCH": "1",
                "OPENCODE_CONFIG_PROJECT_DISABLE": "1",
            }
            for directory in (root / "home", root / "tmp"):
                directory.mkdir()
            subprocess.run(["git", "init", "-q"], cwd=repo, env=env, check=True)
            version = subprocess.check_output([binary, "--version"], cwd=repo, env=env, text=True).strip()
            self.assertTrue(version.startswith("opencode v2."), version)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            command = [binary, "run", "--standalone", "--format", "json", "--title", "Synthetic RTK roundtrip",
                       "Run git status --short using the shell tool, then report the result."]
            try:
                result = subprocess.run(command, cwd=repo, env=env, capture_output=True, text=True, timeout=60)
            finally:
                server.shutdown()
                thread.join(timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertFalse(protocol_errors, protocol_errors)
            self.assertEqual(len(requests), 2, "expected one toolcall followed by model continuation")
            self.assertEqual(len(tool_results), 1, "model never received an actual shell-tool result")
            self.assertIn(MARKER, json.dumps(tool_results))
            self.assertIn(SUCCESS, result.stdout, "final model response missing")
            events = [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]
            self.assertTrue(any(COMMAND in json.dumps(event) and MARKER in json.dumps(event)
                                for event in events), "native CLI never reported original command + shell output")
            calls = [json.loads(line) for line in trace.read_text().splitlines()]
            self.assertIn(["rewrite", COMMAND], calls, "managed plugin never ran the post-permission RTK shim")
            self.assertIn(["git", "status", "--short"], calls, "rewritten command never executed real RTK")
            self.assertFalse((root / "state/opencode/service.json").exists(), "standalone registered a shared service")
            print(f"PASS: {version}; actual native shell output reached model; real RTK rewrite/execution after exact original-command allow")
            print("COMMAND:", shlex.join(command))


if __name__ == "__main__":
    unittest.main()
