"""Resume, create or delete tmux sessions, organized by their starting folder."""
import argparse
from datetime import datetime
import os
import re
import subprocess
import sys


DEFAULT_FOLDER = "/fast/compute/erik/Documents"


def tmux(*arguments):
    environment = os.environ.copy()
    if arguments[0] == "list-sessions":
        environment["LC_ALL"] = "C.UTF-8"
    return subprocess.run(["tmux", *arguments], capture_output=True, text=True, env=environment)


def delete_session(identity, created, server_pid):
    # Server restarts reuse session IDs, so check identity inside tmux before killing.
    condition = "#{&&:#{==:#{session_created}," + created + "},#{==:#{pid}," + server_pid + "}}"
    result = tmux("if-shell", "-F", "-t", identity, condition,
                  f"kill-session -t '{identity}'",
                  "display-message -p 'Session changed; select it again.'")
    if result.stdout.strip() or result.stderr.strip():
        print(result.stdout.strip() or result.stderr.strip(), file=sys.stderr)


def attach(identity):
    command = "switch-client" if os.environ.get("TMUX") else "attach-session"
    os.execvp("tmux", ["tmux", command, "-t", identity])
    return 0


def create_session(folder):
    folder = input(f"Starting folder [{folder}]: ").strip() or folder
    folder = os.path.realpath(os.path.expanduser(folder))
    if not os.path.isdir(folder):
        print(f"Not a directory: {folder}", file=sys.stderr)
        return
    name = input("Session name [automatic]: ").strip()
    command = ["new-session", "-d", "-P", "-F", "#{session_id}", "-c", folder]
    if name:
        command += ["-s", name]
    result = tmux(*command)
    if result.returncode:
        print(result.stderr.strip(), file=sys.stderr)
        return
    return result.stdout.strip()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", nargs="?", help="show only sessions started in this folder")
    args = parser.parse_args(argv)
    picker_env = os.environ.copy()
    for name in ("FZF_DEFAULT_OPTS", "FZF_DEFAULT_OPTS_FILE"):
        picker_env.pop(name, None)
    while True:
        listing = tmux("list-sessions", "-F", "#{session_id}\t#{session_name}\t#{session_path}\t#{session_attached}\t#{session_created}\t#{pid}")
        if listing.returncode:
            missing_server = listing.stderr.strip() == "no sessions" or "no server running on " in listing.stderr or (
                "error connecting to " in listing.stderr and ("No such file or directory" in listing.stderr or "Connection refused" in listing.stderr)
            )
            if not missing_server:
                print(listing.stderr.strip() or "Cannot list tmux sessions.", file=sys.stderr)
                return 1
        sessions = {}
        for line in listing.stdout.splitlines():
            fields = line.split("\t")
            if len(fields) != 6:
                continue
            identity, name, folder, attached, created, server_pid = fields
            if not re.fullmatch(r"\$[0-9]+", identity) or not re.fullmatch(r"[0-9]+", created) or not re.fullmatch(r"[0-9]+", server_pid):
                continue
            if args.folder and os.path.realpath(folder) != os.path.realpath(args.folder):
                continue
            age = datetime.fromtimestamp(int(created)).strftime("%Y-%m-%d %H:%M")
            sessions[identity] = (folder, name, "attached" if attached != "0" else "detached", age, created, server_pid)
        rows = "+\tNew session…\n" + "".join(
            "\t".join((identity, *details[:4])) + "\n"
            for identity, details in sorted(sessions.items(), key=lambda item: item[1])
        )
        choice = subprocess.run(
            ["fzf", "--delimiter=\t", "--with-nth=2..", "--no-sort", "--prompt=Resume> ",
             "--expect=ctrl-n,ctrl-d", "--header=Folder / session / status / created — Enter attach; Ctrl-N new; Ctrl-D delete; Esc cancel"],
            input=rows, capture_output=True, text=True, env=picker_env,
        )
        if choice.returncode in (1, 130):
            return 0
        if choice.returncode:
            print(choice.stderr.strip() or "Session picker failed.", file=sys.stderr)
            return choice.returncode
        lines = choice.stdout.splitlines()
        key = lines[0] if lines else ""
        identity = lines[1].split("\t", 1)[0] if len(lines) > 1 else ""
        try:
            if key == "ctrl-n" or (key == "" and identity == "+"):
                created = create_session(args.folder or DEFAULT_FOLDER)
                if created:
                    return attach(created)
                continue
            if key == "ctrl-d" and identity == "+":
                continue
            if identity not in sessions:
                print("Selected session is no longer in the session list.", file=sys.stderr)
                return 1
            if key == "ctrl-d":
                folder, name, state, _, created, server_pid = sessions[identity]
                answer = input(f"Delete {name!r} ({state}) in {folder}? This terminates its running processes. Type DELETE: ")
                if answer == "DELETE":
                    delete_session(identity, created, server_pid)
                continue
            return attach(identity)
        except (EOFError, KeyboardInterrupt):
            print()
            return 0


if __name__ == "__main__":
    sys.exit(main())
