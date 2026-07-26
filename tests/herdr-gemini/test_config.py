from pathlib import Path


ROOT = Path(__file__).parents[2]
MODULE = ROOT / "modules/dev/herdr-gemini.nix"


def test_gemini_owns_pinned_plugins_and_default_sessions():
    source = MODULE.read_text()

    assert 'plusVersion = "0.1.20"' in source
    assert 'navigatorVersion = "0.3.3"' in source
    assert '"homelab" "dataplatform"' in source
    assert 'ExecStart = "${herdr}/bin/herdr --session %i server"' in source


def test_repo_launcher_creates_persistent_remote_named_session():
    source = MODULE.read_text()
    herdr = (ROOT / "modules/dev/herdr.nix").read_text()

    assert 'name = "herdr-repo"' in herdr
    assert "rev-parse --show-toplevel" in herdr
    assert "herdr-repo-bootstrap" in herdr
    assert "systemctl --user enable --now" in source
    assert 'workspace create --cwd "$remote_repo"' in source
    assert 'exec herdr --remote gemini --session "$session"' in herdr


def test_navigation_uses_plus_projects_and_one_global_picker():
    source = MODULE.read_text()

    herdr = (ROOT / "modules/dev/herdr.nix").read_text()

    assert 'cloudmanic.herdr-plus.projects' in herdr
    assert 'herdr-navigator.open' in herdr
    assert 'key = "prefix+t"' in herdr
    assert 'homelab = "~/Documents/erik/homelab"' in source
    assert 'dataplatform = "~/Documents/nstech/dataplatform"' in source


def test_gemini_imports_remote_session_profile_with_linger():
    gemini = (ROOT / "modules/hosts/orion/gemini.nix").read_text()

    assert "m.home.herdr-gemini" in gemini
    assert "linger = true;" in gemini


def test_shared_aliases_expose_default_and_repo_sessions():
    aliases = (ROOT / "modules/shell/_aliases.nix").read_text()

    assert 'hlab = "herdr --remote gemini --session homelab";' in aliases
    assert 'hdap = "herdr --remote gemini --session dataplatform";' in aliases
    assert 'hr = "herdr-repo";' in aliases
