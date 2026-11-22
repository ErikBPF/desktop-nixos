"""Choose an existing tmux session by its starting folder and session name."""
import argparse
import os
import subprocess
import sys


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", nargs="?", help="show only sessions started in this folder")
    args = parser.parse_args(argv)
    listing = subprocess.run(
        ["tmux", "list-sessions", "-F", "#{session_id}\t#{session_name}\t#{session_path}\t#{session_attached}"],
        capture_output=True, text=True,
    )
    if listing.returncode:
        print(listing.stderr.strip() or "No tmux sessions available.", file=sys.stderr)
        return 1
    sessions = {}
    for line in listing.stdout.splitlines():
        fields = line.split("\t")
        if len(fields) != 4:
            continue
        identity, name, folder, attached = fields
        if args.folder and os.path.realpath(folder) != os.path.realpath(args.folder):
            continue
        sessions[identity] = (folder, name, "attached" if attached != "0" else "detached")
    if not sessions:
        print("No tmux sessions match this folder.", file=sys.stderr)
        return 1
    rows = "".join(
        "\t".join((identity, *details)) + "\n"
        for identity, details in sorted(sessions.items(), key=lambda item: item[1])
    )
    picker_env = os.environ.copy()
    for name in ("FZF_DEFAULT_OPTS", "FZF_DEFAULT_OPTS_FILE"):
        picker_env.pop(name, None)
    choice = subprocess.run(
        ["fzf", "--delimiter=\t", "--with-nth=2..", "--no-sort", "--prompt=Resume> ",
         "--header=Folder / session / status — Enter attach; Esc cancel"],
        input=rows, capture_output=True, text=True, env=picker_env,
    )
    if choice.returncode in (1, 130):
        return 0
    if choice.returncode:
        print(choice.stderr.strip() or "Session picker failed.", file=sys.stderr)
        return choice.returncode
    identity = choice.stdout.split("\t", 1)[0].strip()
    if identity not in sessions:
        print("Selected session is no longer in the session list.", file=sys.stderr)
        return 1
    command = "switch-client" if os.environ.get("TMUX") else "attach-session"
    os.execvp("tmux", ["tmux", command, "-t", identity])
    return 0


if __name__ == "__main__":
    sys.exit(main())
