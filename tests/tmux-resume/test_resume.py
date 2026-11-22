"""Picker contracts: folder identity, exact selection, cancel and nesting."""
import importlib.util
import os
from pathlib import Path
import subprocess
import unittest
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
        listing = "$2\twork\t/compute/work/project\t1\n$1\thome\t/compute/home/project\t0\n"
        results = [subprocess.CompletedProcess([], 0, listing, ""),
                   subprocess.CompletedProcess([], selection[0], selection[1], "")]
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
