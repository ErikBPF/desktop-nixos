from pathlib import Path


ROOT = Path(__file__).parents[2]
MODULE = ROOT / "modules/dev/tuicr.nix"


def test_module_installs_tuicr_with_nix_owned_config():
    assert MODULE.exists()

    module = MODULE.read_text()
    assert "home.packages = [pkgs.tuicr];" in module
    assert 'no_update_check = true;' in module
    assert 'diff_watch_interval_ms = 1000;' in module


def test_codex_gets_the_version_matched_tuicr_skill():
    module = MODULE.read_text()

    assert 'home.file.".agents/skills/tuicr".source' in module
    assert '"${pkgs.tuicr.src}/skills/tuicr"' in module
    assert "codex plugin" not in module


def test_developer_profiles_and_shortcut_enable_working_tree_reviews():
    desktop = (ROOT / "modules/profiles/desktop.nix").read_text()
    gemini = (ROOT / "modules/hosts/orion/gemini.nix").read_text()
    aliases = (ROOT / "modules/shell/_aliases.nix").read_text()

    assert "m.home.tuicr" in desktop
    assert "m.home.tuicr" in gemini
    assert 'tcr = "tuicr -w";' in aliases
