from pathlib import Path


ROOT = Path(__file__).parents[2]
MODEL = "deepseek-v4-flash"


def test_opencode_defaults_to_deepseek_v4_flash_through_litellm():
    source = (ROOT / "modules/dev/opencode.nix").read_text()

    assert f'model = "litellm/{MODEL}";' in source
    assert f'{MODEL} = {{' in source


def test_qwen_chat_exposes_orion_context():
    source = (ROOT / "modules/dev/opencode.nix").read_text()
    qwen_chat = source.split("qwen-chat = {", 1)[1].split("qwen-embed = {", 1)[0]

    assert "context = 98304;" in qwen_chat


def test_all_hermes_brains_default_to_deepseek_v4_flash():
    primary = (ROOT / "modules/hosts/discovery/hermes-oci.nix").read_text()
    agents = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()

    assert f'default = "{MODEL}";' in primary
    assert f'default = "{MODEL}";' in agents
