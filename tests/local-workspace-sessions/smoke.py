"""Exercise isolated native tmux sessions without running real coding agents."""

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import time
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("workspace_sessions", ROOT / "modules/desktop/_workspace-sessions.py")
APP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(APP)


def main():
    with tempfile.TemporaryDirectory(prefix="workspace-tmux-smoke-") as temporary:
        root = Path(temporary)
        binaries = root / "bin"
        binaries.mkdir()
        for program in ("agent shim", "tuicr", "nvim"):
            executable = binaries / program
            executable.write_text("#!/bin/sh\nexit 0\n")
            executable.chmod(0o700)
        tmux_config = root / "tmux.conf"
        tmux_config.write_text('set -g default-shell /bin/sh\nset -g default-command ""\nset -g destroy-unattached off\nset -s exit-unattached off\n')
        config = {"defaultCodingAgent": str(binaries / "agent shim"), "shell": "/bin/sh", "projects": []}
        for project, code, review in (("work", 2, 3), ("lab", 7, 8)):
            directory = root / (project + " project")
            directory.mkdir()
            config["projects"].append(dict(name=project, directory=str(directory), workspaces=[code, review], code=code, review=review))
        environment = {**os.environ, "HOME": str(root), "XDG_CONFIG_HOME": str(root / "config"),
                       "TMUX_TMPDIR": str(root), "TMUX": str(root / "foreign") + ",1,0",
                       "PATH": str(binaries) + os.pathsep + os.environ["PATH"], "TERM": "xterm-256color"}
        with patch.dict(os.environ, environment, clear=True):
            server = subprocess.Popen(["tmux", "-D", "-L", "workspace-desktop", "-f", str(tmux_config)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            prefix = ["tmux", "-N", "-L", "workspace-desktop"]
            try:
                for _, name, _ in APP.sessions(config):
                    APP.bootstrap(config, name)
                def snapshot():
                    output = APP.run(*prefix, "list-panes", "-a", "-F", "#{session_name}\t#{pane_id}\t#{pane_pid}\t#{pane_current_command}\t#{pane_current_path}").stdout
                    return [line.split("\t") for line in output.splitlines()]
                for _ in range(50):
                    before = snapshot()
                    if all(row[3] == "sh" for row in before):
                        break
                    time.sleep(0.02)
                assert len(before) == 20 and len({row[0] for row in before}) == 20, before
                assert all(row[3] == "sh" for row in before), "Exited applications did not return to shells"
                assert all(Path(row[4]) == root / (row[0].split("-", 1)[0] + " project") for row in before), "Wrong project cwd"
                for row in before:
                    parent = Path(f"/proc/{row[2]}/stat").read_text().rsplit(")", 1)[1].split()[1]
                    assert int(parent) == server.pid, "Pane is not owned by the dedicated backend"
                for _, name, _ in APP.sessions(config):
                    APP.bootstrap(config, name)
                assert before == snapshot(), "Repeated bootstrap changed session identity/processes"
                # A control-mode client is a real frontend without requiring a GUI/TTY.
                client_env = {key: value for key, value in environment.items() if key != "TMUX"}
                client = subprocess.Popen([*prefix, "-C", "attach-session", "-t", "=work-shell-1"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=client_env)
                try:
                    for _ in range(50):
                        attached = APP.run(*prefix, "list-clients", "-F", "#{client_pid}").stdout.splitlines()
                        if str(client.pid) in attached:
                            break
                        time.sleep(0.02)
                    assert str(client.pid) in attached, "Control frontend did not attach"
                finally:
                    client.terminate()
                    client.communicate(timeout=5)
                assert server.poll() is None and before == snapshot(), "Frontend exit stopped backend work"
                # Native exact targeting must not treat a prefix as an existing session.
                result = subprocess.run([*prefix, "has-session", "-t", "=work-shell"], capture_output=True)
                assert result.returncode != 0, "Exact session matching accepted a prefix"
                assert not (root / "foreign").exists(), "Inherited foreign socket was used"
                print("PASS: 20 independent one-pane sessions, quoted commands return to shells, cwd and repeat identity preserved")
                print("PASS: dedicated backend owns panes; frontend exit preserves them; exact targets ignore foreign socket")
            finally:
                subprocess.run([*prefix, "kill-server"], capture_output=True, timeout=5)
                try:
                    server.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    server.terminate()
                    server.communicate(timeout=5)
            result = subprocess.run([*prefix, "new-session", "-d", "-s", "must-not-start"], capture_output=True)
            assert result.returncode != 0, "Client unexpectedly autostarted a server"
            print("PASS: -N cannot autostart after backend shutdown; no real agents or graphical windows exercised")


if __name__ == "__main__":
    main()
