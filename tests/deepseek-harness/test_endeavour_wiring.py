from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/dev/deepseek-harness.nix"


def test_endeavour_tui_uses_the_secretspec_environment():
    source = MODULE.read_text()

    assert 'writeShellApplication' in source
    assert 'name = "dsh-tui";' in source
    assert '(lib.hiPrio tui)' in source
    assert 'exec ${harness}/bin/dsh-tui "$@"' in source
    assert 'secretspec run' not in source
    assert 'provider = "keyring"' not in source
    assert 'keyring = "keyring://"' not in source
    assert 'xdg.configFile."secretspec/config.toml".text' not in source
    assert 'dsh-tui = "dsh-tui-homelab";' not in source
    assert 'ssh' not in source
    assert '/run/vault-agent/token' not in source
    assert 'LITELLM_MASTER_KEY' not in source
