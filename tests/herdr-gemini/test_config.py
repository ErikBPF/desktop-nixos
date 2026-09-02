import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).parents[2]
MODULE = ROOT / "modules/dev/herdr-worklab.nix"
GALAXY_S25_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHzKv0yi/MC6TpRB3w2BAGYJw1gELHQSJuna9r8d0j8/"
GEMINI_SYNCTHING_ID = "3MXXNKD-O7PXY6E-2SKDLDF-7SJXAYJ-JNLLF2O-YZU2Y33-UKKXTOV-5HD3ZAF"


def nix_eval(attribute):
    result = subprocess.run(
        ["nix", "eval", "--json", f"{ROOT}#{attribute}"],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def test_gemini_owns_pinned_plugins_and_default_sessions():
    source = MODULE.read_text()

    assert 'plusVersion = "0.1.20"' in source
    assert 'navigatorVersion = "0.3.6"' in source
    assert '"homelab" "dataplatform"' in source
    assert 'ExecStart = "${herdr}/bin/herdr --session %i server"' in source


def test_default_session_bootstrap_exports_herdr_socket_path():
    source = MODULE.read_text()

    assert 'export HERDR_SOCKET_PATH="$HOME/.config/herdr/sessions/$session/herdr.sock"' in source
    assert 'herdr-plus open "$project" || echo "herdr project $project is unavailable; session remains attachable" >&2' in source


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


def test_herdr_has_direct_directional_pane_navigation():
    herdr = (ROOT / "modules/dev/herdr.nix").read_text()

    assert 'focus_pane_left = ["prefix+h" "alt+left"];' in herdr
    assert 'focus_pane_right = ["prefix+l" "alt+right"];' in herdr
    assert 'focus_pane_up = ["prefix+k" "alt+up"];' in herdr
    assert 'focus_pane_down = ["prefix+j" "alt+down"];' in herdr


def test_vim_and_herdr_share_ctrl_directional_navigation():
    herdr = (ROOT / "modules/dev/herdr.nix").read_text()

    assert 'rev = "820d48f5d9c9a7dece6a4bebfa3982ec30bbfbb7"' in herdr
    assert "plugin link ${vimHerdrNavigation}" in herdr
    assert '"nvim/after/plugin/herdr_nav.lua"' in herdr
    for direction, key in [
        ("left", "h"),
        ("down", "j"),
        ("up", "k"),
        ("right", "l"),
    ]:
        assert f'key = "ctrl+{key}"' in herdr
        assert f'command = "vim-herdr-navigation.{direction}"' in herdr


def test_gemini_imports_remote_session_profile_with_linger():
    gemini = (ROOT / "modules/hosts/orion/gemini.nix").read_text()

    assert "m.home.herdr-worklab" in gemini
    assert "linger = true;" in gemini


def test_galaxy_s25_key_is_scoped_to_gemini_user():
    erik_keys = nix_eval(
        "nixosConfigurations.orion.config.containers.gemini.config.users.users.erik.openssh.authorizedKeys.keys"
    )
    root_keys = nix_eval(
        "nixosConfigurations.orion.config.containers.gemini.config.users.users.root.openssh.authorizedKeys.keys"
    )

    assert GALAXY_S25_KEY in erik_keys
    assert GALAXY_S25_KEY not in root_keys


def test_galaxy_s25_key_is_scoped_to_endeavour_user():
    erik_keys = nix_eval(
        "nixosConfigurations.endeavour.config.users.users.erik.openssh.authorizedKeys.keys"
    )
    root_keys = nix_eval(
        "nixosConfigurations.endeavour.config.users.users.root.openssh.authorizedKeys.keys"
    )

    assert GALAXY_S25_KEY in erik_keys
    assert GALAXY_S25_KEY not in root_keys


def test_galaxy_s25_key_is_scoped_to_orion_user():
    erik_keys = nix_eval(
        "nixosConfigurations.orion.config.users.users.erik.openssh.authorizedKeys.keys"
    )
    root_keys = nix_eval(
        "nixosConfigurations.orion.config.users.users.root.openssh.authorizedKeys.keys"
    )

    assert GALAXY_S25_KEY in erik_keys
    assert GALAXY_S25_KEY not in root_keys


def test_endeavour_uses_live_gemini_syncthing_identity():
    device_id = nix_eval(
        "nixosConfigurations.endeavour.config.services.syncthing.settings.devices.gemini.id"
    )

    assert device_id == GEMINI_SYNCTHING_ID


def test_shared_aliases_expose_default_and_repo_sessions():
    aliases = (ROOT / "modules/shell/_aliases.nix").read_text()

    assert 'h = "herdr session attach homelab";' in aliases
    assert 'hg = "herdr --remote gemini --session homelab";' in aliases
    assert 'hgs = "ssh -t gemini \'exec herdr session attach homelab\'";' in aliases
    assert 'hlab = "herdr --remote gemini --session homelab";' in aliases
    assert 'hdap = "herdr --remote gemini --session dataplatform";' in aliases
    assert 'hr = "herdr-repo";' in aliases
    assert "--session code" not in aliases
    assert "session attach code" not in aliases


def test_opencode_native_restore_integration_is_declarative():
    gemini = MODULE.read_text()
    herdr = (ROOT / "modules/dev/herdr.nix").read_text()

    assert '"opencode/plugins/herdr-agent-state.js".source' in gemini
    assert 'inputs.herdr + "/src/integration/assets/opencode/herdr-agent-state.js"' in gemini
    assert "opencode/plugins/herdr-agent-state.js" not in herdr
    assert "herdr integration install opencode" not in herdr


def test_herdr_pane_history_is_explicitly_disabled():
    herdr = (ROOT / "modules/dev/herdr.nix").read_text()

    assert "experimental.pane_history = false;" in herdr


def test_gemini_herdr_preflight_is_value_free_and_fail_closed():
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("verify-gemini-herdr:", 1)[1].split("\n\n", 1)[0]

    assert "herdr integration status" in recipe
    assert "opencode: current (" in recipe
    assert "herdr-session-homelab.service" in recipe
    assert "herdr-session-dataplatform.service" in recipe
    for forbidden in ("printenv", "config.toml", "session.json", "auth.json"):
        assert forbidden not in recipe
