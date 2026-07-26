from pathlib import Path


HYPRLAND = Path("modules/desktop/hyprland.nix").read_text()


def test_default_apps_are_batched_by_monitor():
    assert 'hl.exec_cmd("systemctl --user restart quickshell")' not in HYPRLAND
    assert 'browser .. " --restore-last-session", { workspace = 1 }' in HYPRLAND
    assert '"sleep 2; " .. teamsApp, { workspace = 10 }' in HYPRLAND
    assert '"sleep 2; discord", { workspace = 10 }' in HYPRLAND
    assert '"sleep 2; " .. whatsappApp, { workspace = 10 }' in HYPRLAND
    assert '"sleep 4; ghostty +new-window -e btop", { workspace = 11 }' in HYPRLAND
    assert '"sleep 4; obsidian", { workspace = 11 }' in HYPRLAND
    assert '"sleep 6; ghostty --gtk-single-instance=false' in HYPRLAND
