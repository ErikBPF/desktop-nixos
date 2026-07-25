import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).parents[2]
HYPRLAND = ROOT / "modules/desktop/hyprland.nix"
YAZI_DESKTOP = ROOT / "modules/desktop/yazi-desktop.nix"
YAZI_RESUME = ROOT / "modules/desktop/_yazi-resume.sh"


def test_desktop_shortcuts_and_environment():
    hyprland = HYPRLAND.read_text()

    assert '"XDG_DATA_DIRS"' not in hyprland
    assert 'fileManager = {_var = "nautilus";};' in hyprland
    assert (
        'fileManagerTui = {_var = "ghostty +new-window -e yazi-resume";};'
        in hyprland
    )
    assert '"SUPER + E" (mkLuaInline "hl.dsp.exec_cmd(fileManager)")' in hyprland
    assert (
        '"SUPER + SHIFT + E" (mkLuaInline "hl.dsp.exec_cmd(fileManagerTui)")'
        in hyprland
    )


def test_yazi_launcher_resumes_last_directory(tmp_path):
    home = tmp_path / "home"
    first = tmp_path / "first"
    second = tmp_path / "second"
    fake_bin = tmp_path / "bin"
    for directory in (home, first, second, fake_bin):
        directory.mkdir()

    fake_yazi = fake_bin / "yazi"
    fake_yazi.write_text(
        "#!/usr/bin/env bash\n"
        'printf "%s\\n" "$1" >> "$YAZI_START_LOG"\n'
        'printf "%s\\n" "$YAZI_FAKE_CWD" > "$3"\n'
    )
    fake_yazi.chmod(0o755)

    env = os.environ | {
        "HOME": str(home),
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "XDG_STATE_HOME": str(tmp_path / "state"),
        "YAZI_START_LOG": str(tmp_path / "starts"),
        "YAZI_FAKE_CWD": str(first),
    }
    subprocess.run(["bash", YAZI_RESUME], check=True, env=env)
    env["YAZI_FAKE_CWD"] = str(second)
    subprocess.run(["bash", YAZI_RESUME], check=True, env=env)

    assert (tmp_path / "starts").read_text().splitlines() == [
        str(home),
        str(first),
    ]
    assert (
        tmp_path / "state/yazi/last-cwd"
    ).read_text().strip() == str(second)


def test_resume_launcher_is_installed():
    assert "builtins.readFile ./_yazi-resume.sh" in YAZI_DESKTOP.read_text()
