from pathlib import Path


ROOT = Path(__file__).parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text()


def test_monitor_layouts_are_home_modules():
    layouts = read("modules/desktop/monitor-layouts.nix")
    assert "flake.modules.home.monitor-layout-docked" in layouts
    assert "flake.modules.home.monitor-layout-pathfinder" in layouts
    assert "m.home.monitor-layout-docked" in read("modules/hosts/laptop/default.nix")
    assert "m.home.monitor-layout-docked" in read("modules/hosts/endeavour/default.nix")
    assert "m.home.monitor-layout-pathfinder" in read(
        "modules/hosts/pathfinder/default.nix"
    )


def test_reusable_modules_do_not_live_under_hosts():
    assert (ROOT / "modules/services/netbird-relay.nix").exists()
    assert (ROOT / "modules/services/hermes-client.nix").exists()
    assert (ROOT / "modules/services/opencode-client.nix").exists()
    assert not (ROOT / "modules/hosts/voyager/netbird-relay.nix").exists()
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
