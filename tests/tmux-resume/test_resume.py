"""Picker contracts: folder identity, exact selection, cancel and nesting."""
import importlib.util
import os
from pathlib import Path
import subprocess
import unittest
import tempfile
import shutil
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


class Resume(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = ROOT / "modules/terminal/_tmux-resume.py"
        spec = importlib.util.spec_from_file_location("tmux_resume", path)
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def invoke(self, selection, inside=False, folder=None):
        listing = "$2\twork\t/compute/work/project\t1\t1700000000\t1234\n$1\thome\t/compute/home/project\t0\t1700000000\t1234\n"
        results = [subprocess.CompletedProcess([], 0, listing, ""),
                   subprocess.CompletedProcess([], selection[0], "\n" + selection[1], "")]
        environment = {"FZF_DEFAULT_OPTS": "--filter=work", "FZF_DEFAULT_OPTS_FILE": "/tmp/custom-fzf"}
        if inside:
            environment["TMUX"] = "socket,123,0"
        with patch.dict(os.environ, environment, clear=True), patch.object(
            self.module.subprocess, "run", side_effect=results
        ) as run, patch.object(self.module.os, "execvp") as execute:
            status = self.module.main([] if folder is None else [folder])
        return status, run.call_args_list, execute.call_args_list

    def test_folders_with_same_basename_stay_distinct(self):
        _, calls, execute = self.invoke((0, "$2\t/compute/work/project\twork\tattached\n"))
        rows = calls[1].kwargs["input"]
        self.assertIn("/compute/home/project", rows)
        self.assertIn("/compute/work/project", rows)
        self.assertLess(rows.index("/compute/home/project"), rows.index("/compute/work/project"))
        self.assertEqual(execute[0].args, ("tmux", ["tmux", "attach-session", "-t", "$2"]))

    def test_cancel_does_not_attach_or_create(self):
        status, _, execute = self.invoke((130, ""))
        self.assertEqual(status, 0)
        self.assertEqual(execute, [])

    def test_inside_tmux_switches_without_nesting(self):
        _, _, execute = self.invoke((0, "$1\tanything\n"), inside=True)
        self.assertEqual(execute[0].args[1], ["tmux", "switch-client", "-t", "$1"])

    def test_folder_filter_is_exact(self):
        _, calls, _ = self.invoke((130, ""), folder="/compute/home/project")
        self.assertIn("/compute/home/project", calls[1].kwargs["input"])
        self.assertNotIn("/compute/work/project", calls[1].kwargs["input"])

    def test_unknown_selection_is_not_executed(self):
        status, _, execute = self.invoke((0, "$99\tforged\n"))
        self.assertEqual(status, 1)
        self.assertEqual(execute, [])

    def test_user_fzf_defaults_cannot_auto_select(self):
        _, calls, _ = self.invoke((130, ""))
        self.assertIn("env", calls[1].kwargs)
        self.assertNotIn("FZF_DEFAULT_OPTS", calls[1].kwargs["env"])
        self.assertNotIn("FZF_DEFAULT_OPTS_FILE", calls[1].kwargs["env"])

    def action(self, replies, answers=(), inside=False):
        environment = {"TMUX": "socket,1,0"} if inside else {}
        with patch.dict(os.environ, environment, clear=True), patch.object(
            self.module.subprocess, "run", side_effect=replies
        ) as run, patch.object(self.module.os, "execvp") as execute, patch(
            "builtins.input", side_effect=answers
        ):
            status = self.module.main([])
        return status, run.call_args_list, execute.call_args_list

    def test_empty_server_offers_new_without_creating_on_cancel(self):
        status, calls, execute = self.action([
            subprocess.CompletedProcess([], 1, "", "no server running on /tmp/socket"),
            subprocess.CompletedProcess([], 130, "", ""),
        ])
        self.assertEqual(status, 0)
        self.assertEqual(len(calls), 2)
        self.assertIn("New session", calls[1].kwargs["input"])
        self.assertEqual(execute, [])

    def test_new_session_uses_folder_and_name_then_attaches_exact_id(self):
        with tempfile.TemporaryDirectory(prefix="project space ") as folder:
            status, calls, execute = self.action([
                subprocess.CompletedProcess([], 0, "", ""),
                subprocess.CompletedProcess([], 0, "ctrl-n\n", ""),
                subprocess.CompletedProcess([], 0, "$7\n", ""),
            ], [folder, "coding"])
        self.assertEqual(status, 0)
        command = calls[2].args[0]
        self.assertEqual(command[:2], ["tmux", "new-session"])
        self.assertEqual(command[command.index("-c") + 1], folder)
        self.assertEqual(command[command.index("-s") + 1], "coding")
        self.assertEqual(execute[0].args[1], ["tmux", "attach-session", "-t", "$7"])

    def test_delete_requires_explicit_confirmation_and_refreshes(self):
        listing = "$2\twork\t/compute/work/project\t1\t1700000000\t1234\n"
        for answer, expected_kills in [("", 0), ("yes", 0), ("DELETE", 1)]:
            replies = [subprocess.CompletedProcess([], 0, listing, ""),
                       subprocess.CompletedProcess([], 0, "ctrl-d\n$2\trow\n", "")]
            if expected_kills:
                replies.append(subprocess.CompletedProcess([], 0, "", ""))
            replies += [subprocess.CompletedProcess([], 0, listing, ""),
                        subprocess.CompletedProcess([], 130, "", "")]
            with self.subTest(answer=answer):
                status, calls, execute = self.action(replies, [answer])
                kills = [c.args[0] for c in calls if c.args[0][1:2] == ["if-shell"]]
                self.assertEqual(len(kills), expected_kills)
                if kills:
                    self.assertIn("#{session_created},1700000000", kills[0][5])
                    self.assertIn("#{pid},1234", kills[0][5])
                    self.assertEqual(kills[0][6], "kill-session -t '$2'")
                self.assertEqual(status, 0)
                self.assertEqual(execute, [])

    def test_server_error_does_not_offer_new_session(self):
        status, calls, _ = self.action([
            subprocess.CompletedProcess([], 1, "", "permission denied"),
        ])
        self.assertEqual(status, 1)
        self.assertEqual(len(calls), 1)

    def test_delete_on_new_row_only_refreshes(self):
        status, calls, execute = self.action([
            subprocess.CompletedProcess([], 0, "", ""),
            subprocess.CompletedProcess([], 0, "ctrl-d\n+\tNew session\n", ""),
            subprocess.CompletedProcess([], 0, "", ""),
            subprocess.CompletedProcess([], 130, "", ""),
        ])
        self.assertEqual(status, 0)
        self.assertEqual(len(calls), 4)
        self.assertEqual(execute, [])

    @unittest.skipUnless(shutil.which("tmux"), "tmux binary required for real server identity test")
    def test_stale_server_id_cannot_delete_replacement_session(self):
        with tempfile.TemporaryDirectory(prefix="resume-identity-") as folder:
            sockets = [str(Path(folder) / name) for name in ("old", "replacement")]
            def command(socket, *args):
                return subprocess.run(["tmux", "-S", socket, *args], capture_output=True, text=True)
            try:
                for socket in sockets:
                    result = command(socket, "-f", "/dev/null", "new-session", "-d", "-s", "test", "sleep 60")
                    self.assertEqual(result.returncode, 0, result.stderr)
                def identity(socket):
                    result = command(socket, "list-sessions", "-F", "#{session_id} #{session_created} #{pid}")
                    self.assertEqual(result.returncode, 0, result.stderr)
                    return result.stdout.strip().split()
                old, replacement = map(identity, sockets)
                self.assertEqual(old[0], replacement[0])
                self.assertNotEqual(old[2], replacement[2])
                with patch.object(self.module, "tmux", side_effect=lambda *args: command(sockets[1], *args)):
                    self.module.delete_session(*old)
                    self.assertEqual(command(sockets[1], "has-session", "-t", replacement[0]).returncode, 0)
                    self.module.delete_session(*replacement)
                    self.assertNotEqual(command(sockets[1], "has-session", "-t", replacement[0]).returncode, 0)
            finally:
                for socket in sockets:
                    command(socket, "kill-server")
