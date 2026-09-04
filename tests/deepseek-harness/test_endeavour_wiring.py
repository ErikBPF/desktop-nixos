from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/dev/deepseek-harness.nix"


def test_endeavour_tui_uses_the_global_secretspec_provider():
    source = MODULE.read_text()

    assert 'writeShellApplication' in source
    assert 'name = "dsh-tui";' in source
    assert '(lib.hiPrio tui)' in source
    assert 'xdg.configFile."secretspec/config.toml".text' in source
    assert 'provider = "keyring"' in source
    assert 'keyring = "keyring://"' in source
    assert 'LITELLM_HOMELAB_API_KEY = {' in source
    assert '${pkgs.secretspec}/bin/secretspec run' in source
    assert '--provider keyring' in source
    assert '--reason endeavour-deepseek-harness-tui' in source
    assert '-- ${harness}/bin/dsh-tui "$@"' in source
    assert 'dsh-tui = "dsh-tui-homelab";' not in source
    assert 'ssh' not in source
    assert '/run/vault-agent/token' not in source
    assert 'LITELLM_MASTER_KEY' not in source
