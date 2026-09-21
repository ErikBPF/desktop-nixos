"""Behavior bindings for independent desktop tmux sessions."""
import importlib.util
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / "modules/desktop/_workspace-sessions.py"
SPEC = importlib.util.spec_from_file_location("workspace_sessions", SOURCE)
APP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(APP)
PROJECTS = {
    "dataplatform": ("w", 2, [2, 3, 4]),
    "homelab": ("l", 7, list(range(5, 13))),
}
SESSION_NAMES = [f"{prefix}{i}" for prefix, _, _ in PROJECTS.values() for i in range(1, 9)]


class NativeCommands:
    def __init__(self):
        self.calls = []
        self.sessions = {}
        self.workspace = 1
        self.unready = 0
        self.fail_create = False
        self.clients = []
        self.focus = "0xoriginal"
        self.direction = "r"
        self.hide_windows = False
        self.run_shells = []

    def run(self, argv, **kwargs):
        argv = list(argv)
        self.calls.append(argv)
        assert not kwargs.get("shell"), "Commands require argv"
        status, output = 0, ""
        if argv[0] == "tmux":
            assert argv[1:4] == ["-N", "-L", "workspace-desktop"], "Never autostart or use the user's tmux server"
            args = argv[4:]
            if args == ["show-options", "-s", "exit-empty"]:
                if self.unready:
                    self.unready -= 1
                    status = 1
                output = "exit-empty off"
            elif args[0] == "has-session":
                assert args[1] == "-t" and args[2].startswith("="), "Session target must be exact"
                status = int(args[2][1:] not in self.sessions)
            elif args[0] == "new-session":
                if self.fail_create:
                    status = 1
                else:
                    name = args[args.index("-s") + 1]
                    assert name not in self.sessions, "Existing sessions must not be changed"
                    self.sessions[name] = {"panes": 1, "argv": args}
            elif args[0] == "run-shell":
                self.run_shells.append(args[1])
            else:
                raise AssertionError(f"Unexpected tmux mutation: {args}")
        elif argv[0] == "herdr":
            raise AssertionError("Desktop sessions now belong to tmux")
        elif argv[0] == "hyprctl":
            if argv[-1] == "clients":
                output = json.dumps(self.clients)
            elif argv[-1] == "activewindow":
                output = json.dumps({"address": self.focus})
            elif "dispatch" in argv:
                assert len(argv) == 3 and argv[2].startswith("hl.dsp."), "Lua mode requires a dispatcher expression"
                expression = argv[2]
                if expression.startswith("hl.dsp.focus({window = "):
                    self.focus = json.loads(expression.split(" = ", 1)[1][:-2]).removeprefix("address:")
                elif expression.startswith("hl.dsp.layout("):
                    message = json.loads(expression[len("hl.dsp.layout("):-1])
                    if message.startswith("preselect "):
                        self.direction = message.split()[1]
            else:
                output = json.dumps({"id": self.workspace})
        elif argv[:3] == ["systemctl", "--user", "start"] and not self.hide_windows:
            for unit in argv[3:]:
                name = unit.removeprefix("desktop-window-").removesuffix(".service")
                cls = "com.pastelariadev." + name
                if any(c["class"] == cls for c in self.clients):
                    continue
                workspace = 2 if name.startswith("w") else 7
                anchor = next((c for c in self.clients if c["address"] == self.focus and c["workspace"]["id"] == workspace), None)
                size = [1920, 1080]
                if anchor:
                    anchor["size"][0 if self.direction == "r" else 1] /= 2
                    size = anchor["size"].copy()
                client = {"class": cls, "address": f"0x{len(self.clients)+1}", "workspace": {"id": workspace}, "size": size, "floating": False}
                self.clients.append(client)
                self.focus = client["address"]
        if status and kwargs.get("check"):
            raise subprocess.CalledProcessError(status, argv, stderr="native command failed")
        return subprocess.CompletedProcess(argv, status, output, "native command failed" if status else "")


class WorkspaceBehavior(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.config = {"shell": "/bin/sh", "resurrect": "/nix/store/resurrect",
                       "resurrectDir": str(Path(self.temp.name) / "resurrect"), "projects": []}
        for name, (prefix, workspace, workspaces) in PROJECTS.items():
            directory = Path(self.temp.name) / (name + " project")
            directory.mkdir()
            self.config["projects"].append(dict(
                name=name, directory=str(directory), workspaces=workspaces,
                workspace=workspace, prefix=prefix, count=8))
        self.native = NativeCommands()
        self.addCleanup(patch.stopall)
        patch("subprocess.run", side_effect=lambda *a, **kw: self.native.run(*a, **kw)).start()
        patch("time.sleep").start()

    def commands(self, name):
        return [call[4:] for call in self.native.calls if call[0] == "tmux" and call[4] == name]

    def test_sixteen_independent_sessions_with_one_pane_each(self):
        for name in SESSION_NAMES:
            APP.bootstrap(self.config, name)
        self.assertEqual(set(self.native.sessions), set(SESSION_NAMES))
        self.assertTrue(all(session["panes"] == 1 for session in self.native.sessions.values()))
        creates = self.commands("new-session")
        self.assertEqual(len(creates), 16)
        for argv in creates:
            self.assertIn("-d", argv)
            name = argv[argv.index("-s") + 1]
            directory = next(p["directory"] for p in self.config["projects"] if name.startswith(p["prefix"]))
            self.assertEqual(argv[argv.index("-c") + 1], directory)
            self.assertEqual(argv[argv.index("-c") + 2:], [])

    def test_existing_customized_session_is_preserved(self):
        self.native.sessions["l1"] = {"panes": 7, "cwd": "/changed"}
        APP.bootstrap(self.config, "l1")
        self.assertEqual(self.commands("new-session"), [])
        self.assertEqual(self.native.sessions["l1"], {"panes": 7, "cwd": "/changed"})
        self.assertEqual(self.commands("has-session"), [["has-session", "-t", "=l1"]])

    def test_creation_failure_preserves_other_sessions(self):
        self.native.sessions["l2"] = {"panes": 1}
        self.native.fail_create = True
        with self.assertRaises(subprocess.CalledProcessError):
            APP.bootstrap(self.config, "l1")
        self.assertEqual(self.native.sessions, {"l2": {"panes": 1}})

    def test_foreign_session_environment_does_not_select_other_server(self):
        with patch.dict(os.environ, {"TMUX": "/tmp/foreign,123,0", "HERDR_SESSION": "foreign"}):
            APP.bootstrap(self.config, "l1")
            self.assertTrue(self.native.calls)
            for call in self.native.calls:
                self.assertEqual(call[:4], ["tmux", "-N", "-L", "workspace-desktop"])
            self.assertEqual(os.environ["TMUX"], "/tmp/foreign,123,0")

    def test_missing_directory_fails_before_rpc(self):
        Path(self.config["projects"][0]["directory"]).rmdir()
        with self.assertRaises(FileNotFoundError):
            APP.bootstrap(self.config, "w1")
        self.assertEqual(self.native.calls, [])

    def test_readiness_precedes_creation(self):
        self.native.unready = 2
        APP.bootstrap(self.config, "l1")
        self.assertEqual(len(self.commands("show-options")), 3)
        self.assertEqual(len(self.native.sessions), 1)

    def test_readiness_failure_is_bounded(self):
        self.native.unready = 1000
        with self.assertRaises(subprocess.CalledProcessError):
            APP.bootstrap(self.config, "l1")
        self.assertGreater(len(self.native.calls), 1)
        self.assertLess(len(self.native.calls), 1000)
        self.assertEqual(self.native.sessions, {})

    def test_route_terminal_applications_at_workspace_boundaries(self):
        """Route new desktop terminal applications, including Yazi's explicit root."""
        for workspace in [-99, -1, 0, *range(1, 14)]:
            for app in ("shell", "nvim", "yazi"):
                with self.subTest(workspace=workspace, app=app):
                    self.native.workspace = workspace
                    self.native.calls.clear()
                    APP.launch(self.config, app)
                    launches = [call for call in self.native.calls if call[0] == "ghostty"]
                    self.assertEqual(len(launches), 1)
                    launch = launches[0]
                    project = next((item for item in self.config["projects"] if workspace in item["workspaces"]), None)
                    if project:
                        self.assertIn("--working-directory=" + project["directory"], launch)
                        if app == "yazi":
                            self.assertEqual(launch[-3:], ["-e", "yazi", project["directory"]])
                    else:
                        self.assertFalse(any(arg.startswith("--working-directory") for arg in launch))
                        if app == "yazi":
                            self.assertEqual(launch[-2:], ["-e", "yazi-resume"])
                    if app == "nvim":
                        self.assertEqual(launch[-2:], ["-e", "nvim"])
                    if app == "shell":
                        self.assertNotIn("-e", launch)

    def test_existing_workspace_recovery_does_not_rearrange(self):
        self.native.clients = [{"class": "user-window", "address": f"0xu{ws}", "workspace": {"id": ws}, "floating": False, "size": [700, 400]} for ws in (2, 3, 7, 8)]
        with patch.dict(os.environ, {"WAYLAND_DISPLAY": "wayland-test"}):
            APP.recover(self.config)
            APP.recover(self.config)
        starts = [call for call in self.native.calls if call[:3] == ["systemctl", "--user", "start"]]
        self.assertEqual(len(starts), 2)
        for call in starts:
            self.assertEqual(set(call[3:]), {f"desktop-window-{name}.service" for name in SESSION_NAMES})
        self.assertFalse(any("dispatch" in call for call in self.native.calls))
        self.assertEqual(self.native.calls[0][:3], ["systemctl", "--user", "import-environment"])

    def test_empty_workspaces_use_balanced_native_splits_once(self):
        with patch.dict(os.environ, {"WAYLAND_DISPLAY": "wayland-test"}):
            APP.recover(self.config)
        for ws, count, dimensions in ((2, 8, [480, 540]), (7, 8, [480, 540])):
            clients = [c for c in self.native.clients if c["workspace"]["id"] == ws]
            self.assertEqual(len(clients), count)
            self.assertTrue(all(c["size"] == dimensions for c in clients), clients)
        self.assertEqual(self.native.focus, "0xoriginal")
        self.assertEqual(len([call for call in self.native.calls if call[:3] == ["systemctl", "--user", "start"]]), 16)
        self.native.calls.clear()
        with patch.dict(os.environ, {"WAYLAND_DISPLAY": "wayland-test"}):
            APP.recover(self.config)
        self.assertFalse(any("dispatch" in call for call in self.native.calls))

    def test_window_timeout_restores_focus_and_stops_starting(self):
        self.native.hide_windows = True
        with patch.dict(os.environ, {"WAYLAND_DISPLAY": "wayland-test"}):
            with self.assertRaises(RuntimeError):
                APP.recover(self.config)
        self.assertEqual(self.native.focus, "0xoriginal")
        self.assertEqual(len([call for call in self.native.calls if call[:3] == ["systemctl", "--user", "start"]]), 1)
        self.assertLess(len(self.native.calls), 1000)

    def test_recovery_without_display_does_not_import_entire_environment(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(ValueError):
                APP.recover(self.config)
        self.assertEqual(self.native.calls, [])

    def test_concurrent_recovery_does_not_change_focus_or_start_windows(self):
        lock = Path(self.temp.name) / "desktop-workspaces.lock"
        with lock.open("w") as held, patch.dict(os.environ, {"WAYLAND_DISPLAY": "wayland-test", "XDG_RUNTIME_DIR": self.temp.name}):
            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
            APP.recover(self.config)
        self.assertEqual(self.native.calls, [])

    def test_moved_project_windows_are_not_rearranged_or_waited_at_old_workspace(self):
        self.native.clients = [{"class": "com.pastelariadev." + name, "address": f"0xm{i}", "workspace": {"id": 9}, "floating": False, "size": [700, 400]} for i, name in enumerate(SESSION_NAMES)]
        with patch.dict(os.environ, {"WAYLAND_DISPLAY": "wayland-test"}):
            APP.recover(self.config)
        self.assertFalse(any("dispatch" in call for call in self.native.calls))
        self.assertTrue(all(client["workspace"]["id"] == 9 for client in self.native.clients))

    def test_save_runs_resurrect_inside_the_desktop_server(self):
        APP.save(self.config)
        self.assertEqual(self.native.run_shells, ["/nix/store/resurrect/scripts/save.sh"])
        self.assertEqual(self.native.calls[0][:4], ["tmux", "-N", "-L", "workspace-desktop"])

    def test_save_without_server_does_not_autostart(self):
        self.native.unready = 1
        APP.save(self.config)
        self.assertEqual(self.native.run_shells, [])

    def test_restore_without_snapshot_does_nothing(self):
        APP.restore(self.config)
        self.assertEqual(self.native.calls, [])

    def test_restore_replays_snapshot_before_windows(self):
        Path(self.config["resurrectDir"]).mkdir()
        (Path(self.config["resurrectDir"]) / "last").write_text("snapshot")
        APP.restore(self.config)
        self.assertEqual(self.native.run_shells, ["/nix/store/resurrect/scripts/restore.sh"])


if __name__ == "__main__":
    unittest.main()
