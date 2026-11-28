from pathlib import Path


ROOT = Path(__file__).parents[2]
MODEL = "deepseek-v4.1-flash"
ARGUS_IMAGE = "nousresearch/hermes-agent@sha256:444b42594e7f467425872fc35e077a227d377f0fe0726bc818706d62175fad8b"
DAEDALUS_IMAGE = "nousresearch/hermes-agent@sha256:d7800dcb7fe821ba5fb7ec594724a07d3fa972ee2e37092cc9fb8265185c7868"


def test_opencode_defaults_to_deepseek_v4_flash_through_litellm():
    source = (ROOT / "modules/dev/opencode.nix").read_text()

    assert f'model = "litellm/{MODEL}";' in source
    assert f'"{MODEL}" = {{' in source


def test_hermes_brains_default_to_their_documented_models():
    """Pin the effective default per brain, not a string somewhere in the file.

    The review worker (daedalus) overrides the shared default on purpose; a
    bare substring check kept passing while covering no container's effective
    model.
    """
    primary = (ROOT / "modules/hosts/discovery/hermes-oci.nix").read_text()
    agents = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()

    # The shared block that argus and the primary agent inherit.
    assert f'default = "{MODEL}";' in primary
    assert f'default = "{MODEL}";' in agents
    # Daedalus, the review worker, runs on the codex route.
    assert 'model = commonSettings.model // {default = "codex-gpt-6.2-astra";};' in agents
    assert 'agent.reasoning_effort = "high";' in agents


def test_all_hermes_images_include_opencode_session_affinity():
    primary = (ROOT / "modules/hosts/discovery/hermes-oci.nix").read_text()
    agents = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()

    assert primary.count(f'image = "{ARGUS_IMAGE}";') == 1
    assert agents.count(f'image = "{ARGUS_IMAGE}";') == 1
    assert agents.count(f'image = "{DAEDALUS_IMAGE}";') == 1


def test_hermes_marks_litellm_opencode_routes_for_session_affinity():
    primary = (ROOT / "modules/hosts/discovery/hermes-oci.nix").read_text()
    agents = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()

    assert primary.count('provider = "opencode-go";') == 5
    assert primary.count('provider = "custom";') == 1
    assert agents.count('provider = "opencode-go";') == 4
    assert 'provider = "custom";' not in agents


def test_hermes_configs_do_not_reference_removed_litellm_aliases():
    """The 2026-11 catalog contraction removed these routes from LiteLLM."""
    primary = (ROOT / "modules/hosts/discovery/hermes-oci.nix").read_text()
    agents = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()

    for removed in ("qwen-chat", "mimo", "mimo-pro", "kimi-k2-code", "qwen3-max", "minimax-m2", "codex-gpt-6-astra"):
        assert removed not in primary
        assert removed not in agents
