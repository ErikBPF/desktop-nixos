from pathlib import Path


HYPRIDLE = Path("modules/desktop/hypridle.nix").read_text()


def test_dpms_commands_use_lua_dispatchers():
    assert HYPRIDLE.count(r"hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'") == 2
    assert HYPRIDLE.count(r"hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'") == 1
    assert "hyprctl dispatch dpms" not in HYPRIDLE
