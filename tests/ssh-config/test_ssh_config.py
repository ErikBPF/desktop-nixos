from pathlib import Path


SSH_MODULE = Path(__file__).parents[2] / "modules/ssh.nix"


def test_read_only_config_is_replaced_atomically():
    text = SSH_MODULE.read_text()
    assert "mktemp ~/.ssh/config.XXXXXX" in text
    assert 'mv -f "$config_tmp" ~/.ssh/config' in text
