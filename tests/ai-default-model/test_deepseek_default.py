from pathlib import Path


ROOT = Path(__file__).parents[2]
MODEL = "deepseek-v4-flash"
HERMES_IMAGE = "nousresearch/hermes-agent@sha256:d7800dcb7fe821ba5fb7ec594724a07d3fa972ee2e37092cc9fb8265185c7868"


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


def test_all_hermes_images_include_opencode_session_affinity():
    primary = (ROOT / "modules/hosts/discovery/hermes-oci.nix").read_text()
    agents = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()

    assert primary.count(f'image = "{HERMES_IMAGE}";') == 1
    assert agents.count(f'image = "{HERMES_IMAGE}";') == 2


def test_hermes_marks_litellm_opencode_routes_for_session_affinity():
    primary = (ROOT / "modules/hosts/discovery/hermes-oci.nix").read_text()
    agents = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()

    assert primary.count('provider = "opencode-go";') == 10
    assert primary.count('provider = "custom";') == 2
    assert agents.count('provider = "opencode-go";') == 8
    assert 'provider = "custom";' not in agents
