from pathlib import Path


ROOT = Path(__file__).parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text()


def test_ubuntu_laptop_is_not_a_nixos_host():
    assert not (ROOT / "modules/hosts/laptop/default.nix").exists()


def test_endeavour_owns_its_appimage_configuration():
    endeavour = read("modules/hosts/endeavour/default.nix")

    assert "m.nixos.laptop-appimage" not in endeavour
    assert "m.home.laptop-ssh" not in endeavour
    assert "programs.appimage = {" in endeavour


def test_monitor_layouts_are_home_modules():
    layouts = read("modules/desktop/monitor-layouts.nix")
    assert "flake.modules.home.monitor-layout-docked" in layouts
    assert 'output = "eDP-1";' in layouts
    assert 'position = "1400x1680";' in layouts
    assert "scale = 1.25;" not in layouts
    assert "flake.modules.home.monitor-layout-pathfinder" in layouts
    assert "m.home.monitor-layout-docked" in read("modules/hosts/endeavour/default.nix")
    assert "m.home.monitor-layout-pathfinder" in read(
        "modules/hosts/pathfinder/default.nix"
    )


def test_docked_workspace_10_recovers_after_monitor_hotplug():
    layouts = read("modules/desktop/monitor-layouts.nix")
    docked = layouts.split("flake.modules.home.monitor-layout-docked", 1)[1].split(
        "flake.modules.home.monitor-layout-pathfinder", 1
    )[0]

    assert '"monitor.added"' in docked
    assert "m.description ~= c1Description" in docked
    assert "hl.get_workspace(10)" in docked
    assert "hotplugRecoveryDelayMs = 1000;" in docked
    assert "timeout = hotplugRecoveryDelayMs" in docked
    assert docked.count("hl.dsp.workspace.move") == 2
    assert "local wasActive = workspace.active" in docked
    assert "target:set_workspace({ workspace = workspace })" in docked


def test_reusable_modules_do_not_live_under_hosts():
    assert (ROOT / "modules/services/hermes-client.nix").exists()
    assert (ROOT / "modules/services/opencode-client.nix").exists()
    assert not (ROOT / "modules/hosts/laptop/hermes-client.nix").exists()
    assert not (ROOT / "modules/hosts/laptop/opencode-client.nix").exists()


def test_orion_installer_has_its_own_flake_parts_module():
    installer = read("modules/hosts/orion/esp-installer.nix")
    assert "configurations.nixos.orion-esp-installer.module" in installer
    assert "configurations.nixos.orion-esp-installer" not in read(
        "modules/hosts/orion/default.nix"
    )


def test_structure_check_guards_semantic_placement():
    recipe = read("justfile")
    assert ":: reusable names under host directories" in recipe
    assert ":: host-prefixed leaves in profiles" in recipe


def test_syncthing_does_not_sync_git_internal_state():
    ignore = read("modules/common/stignore")

    assert "**/.git" in ignore.splitlines()
    assert ".git is intentionally NOT ignored" not in ignore


def test_syncthing_does_not_sync_local_database_state():
    ignore = read("modules/common/stignore")

    assert "**/.pgdata" in ignore.splitlines()
