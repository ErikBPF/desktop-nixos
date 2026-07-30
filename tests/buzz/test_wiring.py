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
    assert 'BUZZ_RELAY_URL = "http://kepler.netbird.internal:3000";' in module


def test_kepler_exposes_buzz_only_on_netbird():
    host = (ROOT / "modules/hosts/kepler/default.nix").read_text()
    networking = (ROOT / "modules/hosts/kepler/networking.nix").read_text()
    compose = (ROOT / "modules/hosts/kepler/compose.nix").read_text()

    assert "m.nixos.netbird-client" in host
    assert "modules.networking.netbird-client.enable = true" in host
    assert "networking.firewall.interfaces.wt0.allowedTCPPorts = [3000];" in networking
    assert '"buzz"' in compose


def test_kepler_scrapes_buzz_metrics_locally():
    host = (ROOT / "modules/hosts/kepler/default.nix").read_text()
    monitoring = (ROOT / "modules/hosts/kepler/monitoring.nix").read_text()

    assert "m.nixos.kepler-monitoring" in host
    assert 'prometheus.scrape "buzz_relay"' in monitoring
    assert '"__address__" = "127.0.0.1:9102"' in monitoring
    assert '"job"         = "buzz-relay"' in monitoring
    assert '"host"        = "kepler"' in monitoring


def test_buzz_owner_key_uses_openbao_runtime_projection():
    agent = (ROOT / "modules/hosts/discovery/_vault-agent.nix").read_text()
    recipes = (ROOT / "justfile").read_text()

    assert 'secret/data/home/buzz' in agent
    assert 'destination = "/run/vault-agent/buzz-owner.key"' in agent
    assert "seed-buzz-vault" not in recipes
    assert "BUZZ_OWNER_PRIVATE_KEY" not in recipes
