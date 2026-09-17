"""Initialize independent local tmux sessions and route desktop terminal launches."""

import json
import fcntl
import os
from pathlib import Path
import subprocess
import shlex
import sys
import time


def run(*argv):
    return subprocess.run(argv, check=True, text=True, capture_output=True)


def sessions(config):
    for project in config["projects"]:
        for index in range(1, 7):
            yield project, f"{project['name']}-agent-{index}", config["defaultCodingAgent"]
        for index in range(1, 3):
            yield project, f"{project['name']}-shell-{index}", None
        for program in ("tuicr", "nvim"):
            yield project, f"{project['name']}-{program}", program


def bootstrap(config, session):
    project, _, program = next(item for item in sessions(config) if item[1] == session)
    directory = project["directory"]
    if not Path(directory).is_dir():
        raise FileNotFoundError(f"Project directory is unavailable: {directory}")
    prefix = ["tmux", "-N", "-L", "workspace-desktop"]
    for attempt in range(40):
        try:
            run(*prefix, "show-options", "-s", "exit-empty")
            break
        except subprocess.CalledProcessError:
            if attempt == 39:
                raise
            time.sleep(0.25)
    existing = subprocess.run([*prefix, "has-session", "-t", "=" + session], text=True, capture_output=True)
    if existing.returncode == 0:
        return
    launch = "codex --yolo" if program == "codex" else shlex.quote(program or "")
    command = [] if program is None else [launch + "; exec " + shlex.quote(config["shell"])]
    run(*prefix, "new-session", "-d", "-s", session, "-c", directory, *command)


def launch(config, app):
    if app not in ("shell", "nvim", "yazi"):
        raise ValueError(f"Unknown terminal application: {app}")
    workspace = json.loads(run("hyprctl", "-j", "activeworkspace").stdout)["id"]
    project = next((project for project in config["projects"] if workspace in project["workspaces"]), None)
    command = ["ghostty", "+new-window"]
    if project:
        directory = project["directory"]
        if not Path(directory).is_dir():
            raise FileNotFoundError(f"Project directory is unavailable: {directory}")
        command.append("--working-directory=" + directory)
    if app == "nvim":
        command.extend(["-e", "nvim"])
    elif app == "yazi":
        command.extend(["-e", "yazi", project["directory"]] if project else ["-e", "yazi-resume"])
    run(*command)


def recover(config):
    if not os.environ.get("WAYLAND_DISPLAY"):
        raise ValueError("Recovery requires an active Wayland display")
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    with (runtime / "desktop-workspaces.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        recover_windows(config)


def recover_windows(config):
    display_variables = ("WAYLAND_DISPLAY", "DISPLAY", "XDG_CURRENT_DESKTOP",
                         "HYPRLAND_INSTANCE_SIGNATURE", "GTK_THEME", "ADW_DEBUG_COLOR_SCHEME")
    run("systemctl", "--user", "import-environment", *(name for name in display_variables if name in os.environ))
    def clients():
        return json.loads(run("hyprctl", "-j", "clients").stdout)

    initial = clients()
    occupied = {client["workspace"]["id"] for client in initial}
    existing_classes = {client["class"] for client in initial}
    groups = []
    existing = []
    for project in config["projects"]:
        for role in ("code", "review"):
            names = [name for item, name, _ in sessions(config)
                     if item is project and (name.endswith(("-tuicr", "-nvim"))) == (role == "review")]
            if project[role] in occupied or any("com.pastelariadev." + name in existing_classes for name in names):
                existing.extend(names)
            else:
                groups.append((project[role], names))
    original = json.loads(run("hyprctl", "-j", "activewindow").stdout) if groups else {}
    original_workspace = json.loads(run("hyprctl", "-j", "activeworkspace").stdout)["id"] if groups else None
    try:
        for workspace, names in groups:
            run("hyprctl", "dispatch", f"hl.dsp.focus({{workspace = {workspace}}})")
            opened = []
            for name in names:
                if opened:
                    tiled = [client for client in clients() if client["address"] in opened and not client.get("floating")]
                    if tiled:
                        anchor = max(tiled, key=lambda client: client["size"][0] * client["size"][1])
                        run("hyprctl", "dispatch", "hl.dsp.focus({window = " + json.dumps("address:" + anchor["address"]) + "})")
                        direction = "r" if anchor["size"][0] > anchor["size"][1] else "d"
                        run("hyprctl", "dispatch", "hl.dsp.layout(" + json.dumps("preselect " + direction) + ")")
                run("systemctl", "--user", "start", f"desktop-window-{name}.service")
                for _ in range(100):
                    window = next((client for client in clients() if client["class"] == "com.pastelariadev." + name
                                   and client["workspace"]["id"] == workspace), None)
                    if window:
                        opened.append(window["address"])
                        break
                    time.sleep(0.1)
                else:
                    raise RuntimeError(f"Window did not appear: {name}")
        if existing:
            run("systemctl", "--user", "start", *(f"desktop-window-{name}.service" for name in existing))
    finally:
        if groups:
            run("hyprctl", "dispatch", 'hl.dsp.layout("preselect none")')
            if original.get("address"):
                run("hyprctl", "dispatch", "hl.dsp.focus({window = " + json.dumps("address:" + original["address"]) + "})")
            else:
                run("hyprctl", "dispatch", f"hl.dsp.focus({{workspace = {original_workspace}}})")


if __name__ == "__main__":
    try:
        config = json.loads(Path(sys.argv[1]).read_text())
        mode = sys.argv[2]
        if mode == "bootstrap" and len(sys.argv) == 4:
            bootstrap(config, sys.argv[3])
        elif mode == "launch" and len(sys.argv) == 4:
            launch(config, sys.argv[3])
        elif mode == "recover" and len(sys.argv) == 3:
            recover(config)
        else:
            raise ValueError("Usage: desktop-workspaces bootstrap SESSION | recover | launch shell|nvim|yazi")
    except subprocess.CalledProcessError as error:
        print(f"desktop-workspaces: {' '.join(error.cmd)} failed: {(error.stderr or '').strip()}", file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, KeyError, IndexError, StopIteration, RuntimeError) as error:
        print(f"desktop-workspaces: {error or 'Unknown session or missing command'}", file=sys.stderr)
        sys.exit(1)
