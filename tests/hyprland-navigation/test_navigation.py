from pathlib import Path


SOURCE = (Path(__file__).parents[2] / "modules/desktop/hyprland.nix").read_text()


def test_hyprland_navigation_uses_vim_keys_without_arrow_duplicates():
    for key, direction in [("h", "l"), ("j", "d"), ("k", "u"), ("l", "r")]:
        assert f'SUPER + {key}" (mkLuaInline \'\'hl.dsp.focus({{ direction = "{direction}" }})' in SOURCE

    for key in ["left", "right", "up", "down"]:
        assert f"SUPER + {key}" not in SOURCE
        assert f"SUPER + SHIFT + {key}" not in SOURCE

    assert 'SUPER + J" (mkLuaInline \'\'hl.dsp.layout("togglesplit")' not in SOURCE
