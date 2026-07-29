from pathlib import Path


ROOT = Path(__file__).parents[2]


def test_buzz_is_enabled_for_desktops():
    module_path = ROOT / "modules/dev/buzz.nix"
    assert module_path.exists()

    flake = (ROOT / "flake.nix").read_text()
    profile = (ROOT / "modules/profiles/desktop.nix").read_text()
    module = module_path.read_text()

    assert "buzz-flake" in flake
    assert "m.home.buzz" in profile
    assert "inputs.buzz-flake.homeManagerModules.withPackage" in module
    assert "programs.buzz.enable = true" in module


def test_kepler_exposes_buzz_only_on_netbird():
    host = (ROOT / "modules/hosts/kepler/default.nix").read_text()
    networking = (ROOT / "modules/hosts/kepler/networking.nix").read_text()

    assert "m.nixos.netbird-client" in host
    assert "modules.networking.netbird-client.enable = true" in host
    assert "networking.firewall.interfaces.wt0.allowedTCPPorts = [3000];" in networking
