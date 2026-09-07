import os
from pathlib import Path
import shlex
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[2]


def test_repo_launcher_preserves_existing_nonstandard_session(tmp_path):
    """Exercise the real launcher guard against an isolated live tmux server."""
    tmux = shutil.which("tmux")
    assert tmux, "tmux is required for the persistence regression check"
    socket = str(tmp_path / "tmux.sock")
    config = tmp_path / "tmux.conf"
    config.write_text("set -g base-index 1\n")
    command = [tmux, "-S", socket, "-f", str(config)]
    repo = tmp_path / "homelab"
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    subprocess.run(command + ["new-session", "-d", "-s", "homelab", "sleep 60"], check=True)
    try:
        pane = subprocess.check_output(
            command + ["display-message", "-p", "-t", "=homelab:1", "#{pane_id}:#{pane_pid}"],
            text=True,
        )
        bindir = tmp_path / "bin"
        bindir.mkdir()
        wrapper = bindir / "tmux"
        wrapper.write_text("#!/bin/sh\nexec " + shlex.join(command) + ' "$@"\n')
        wrapper.chmod(0o755)
        source = (ROOT / "modules/terminal/tmux.nix").read_text()
        guard = source.split("text = ''", 1)[1].split("          if ! tmux has-session", 1)[0]
        guard = guard.replace("''${", "${")
        result = subprocess.run(
            ["bash", "-eu", "-c", guard, "launcher", str(repo)],
            env=os.environ | {"PATH": f"{bindir}:{os.environ['PATH']}"},
            capture_output=True, text=True,
        )
        after = subprocess.run(
            command + ["display-message", "-p", "-t", "=homelab:1", "#{pane_id}:#{pane_pid}"],
            capture_output=True, text=True,
        )
        assert after.returncode == 0 and after.stdout == pane, "launcher destroyed the running session"
        assert result.returncode == 1 and "refusing to replace" in result.stderr
        hint = result.stderr.split("; use ", 1)[1].strip()
        check_hint = subprocess.run(
            ["zsh", "-f", "-c", hint.replace("tmux attach-session ", "tmux has-session ", 1)],
            env=os.environ | {"PATH": f"{bindir}:{os.environ['PATH']}"},
            capture_output=True, text=True,
        )
        assert check_hint.returncode == 0, check_hint.stderr
    finally:
        subprocess.run(command + ["kill-server"], capture_output=True)
