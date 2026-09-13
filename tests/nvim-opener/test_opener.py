"""Run with python3 tests/nvim-opener/test_opener.py."""

from pathlib import Path
import runpy
from unittest.mock import patch


source = Path(__file__).resolve().parents[2] / "modules/desktop/nvim-open.py"
command = runpy.run_path(source)["command"]
prefix = ["ghostty", "-e", "nvim"]

for targets, expected in [
    (["/tmp/notes.md", "-file.py"], prefix + ["--", "/tmp/notes.md", "-file.py"]),
    (["file:///tmp/hello%20world%20%C3%A9.json"], prefix + ["--", "/tmp/hello world é.json"]),
    (["vscode://file/tmp/a%20b.rs:12:3"], prefix + ["-c", "call cursor(12, 3)", "--", "/tmp/a b.rs"]),
    (["vscode://file/tmp/a.py:12"], prefix + ["-c", "call cursor(12, 1)", "--", "/tmp/a.py"]),
    (["vscode://file/tmp/name%3A12.md"], prefix + ["--", "/tmp/name:12.md"]),
    (["vscode://file/tmp/%24%28touch%20bad%29.py"], prefix + ["--", "/tmp/$(touch bad).py"]),
    (["vscode://vscode.github-authentication/did-authenticate?code=secret"], ["code", "--open-url", "vscode://vscode.github-authentication/did-authenticate?code=secret"]),
]:
    actual = command("ghostty", "nvim", "code", targets)
    assert actual == expected, (targets, actual, expected)

for target in ["file://remote/tmp/a.py", "file:///tmp/a%00.py", "vscode://file"]:
    try:
        command("ghostty", "nvim", "code", [target])
    except ValueError:
        pass
    else:
        raise AssertionError("invalid file URI accepted")

with patch("sys.argv", [str(source), "ghostty", "nvim", "code", "-file é.py"]), patch("os.execv") as execute:
    runpy.run_path(source, run_name="__main__")
    execute.assert_called_once_with("ghostty", prefix + ["--", "-file é.py"])

print("PASS: coding files, URI positions, decoding, argument safety, VSCode auth fallback")
