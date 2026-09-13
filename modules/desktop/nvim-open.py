import os
import re
import sys
from urllib.parse import unquote, urlsplit


def command(terminal, nvim, vscode, targets):
    files = []
    position = []
    for target in targets:
        uri = urlsplit(target)
        if uri.scheme == "vscode" and uri.netloc != "file":
            return [vscode, "--open-url", *targets]
        path = target
        if uri.scheme in ("file", "vscode"):
            if uri.scheme == "file" and uri.netloc not in ("", "localhost"):
                raise ValueError("Only local file URLs can open in Neovim")
            path = uri.path
            if uri.scheme == "vscode":
                match = re.search(r":([0-9]+)(?::([0-9]+))?$", path)
                if match:
                    line, column = match.groups()
                    position = ["-c", f"call cursor({max(1, int(line))}, {max(1, int(column or 1))})"]
                    path = path[:match.start()]
            path = unquote(path)
        if not path or "\0" in path:
            raise ValueError("Invalid file path")
        files.append(path)
    return [terminal, "-e", nvim, *position, "--", *files]


if __name__ == "__main__":
    argv = command(*sys.argv[1:4], sys.argv[4:])
    os.execv(argv[0], argv)
