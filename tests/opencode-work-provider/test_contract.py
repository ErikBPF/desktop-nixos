import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_reasoning_controls_match_gateway_models():
    expression = f'''let
      m = import {ROOT}/modules/dev/opencode.nix {{
        inputs = {{ opencode-flake = {{}}; ponytail = /tmp; }};
      }};
    in (m.flake.modules.home.opencode {{ pkgs = {{}}; }}).programs.opencode.settings.provider'''
    providers = json.loads(subprocess.check_output(
        ["nix", "eval", "--impure", "--json", "--expr", expression], text=True
    ))
    for provider in ("litellm", "work"):
        for name in ("glm-5.3-flash", "deepseek-v4.1-flash"):
            model = providers[provider]["models"][name]
            assert model.get("reasoning") is True, (provider, name)
            variants = model.get("variants", {})
            assert {k for k, v in variants.items() if not v.get("disabled")} == {"low", "high", "max"}
            for effort in ("low", "high", "max"):
                assert variants[effort]["reasoningEffort"] == effort
            assert model["options"]["reasoningEffort"] == "max"
            if name.startswith("deepseek"):
                assert variants["medium"]["disabled"] is True
            if provider == "work":
                assert "reasoning_effort" in model["options"]["allowed_openai_params"]
    for name in ("chatgpt-5.6-luna", "chatgpt-5.6-sol", "chatgpt-5.6-terra"):
        model = providers["work"]["models"][name]
        assert model["reasoning"] is True
        assert model["variants"]["none"]["reasoningEffort"] == "none"


def test_work_litellm_provider_uses_sops_token():
    opencode = (ROOT / "modules/dev/opencode.nix").read_text()
    client = (ROOT / "modules/services/opencode-client.nix").read_text()
    secrets = (ROOT / "secrets/sops/secrets.yaml").read_text()

    assert 'export OPENCODE_WORK_KEY="$(</run/secrets/opencode/work_key)"' in opencode
    assert 'baseURL = "https://llm-gateway-dataplatform-dev.nstech.com.br/v1";' in opencode
    assert 'apiKey = "{env:OPENCODE_WORK_KEY}";' in opencode
    assert 'resource = "work";' in opencode
    work = opencode.split("        work = {", 1)[1].split("        opencode = {", 1)[0]
    for model in ("chatgpt-5.6-luna", "chatgpt-5.6-sol", "chatgpt-5.6-terra",
                  "deepseek-v4.1-flash", "glm-5.3-flash"):
        assert f'"{model}" = {{' in work
    assert work.count('options.reasoningEffort = "none";') == 3
    assert work.count('input = 922000;') == 3
    assert 'context = 1048576;' in work
    assert 'output = 393216;' in work
    assert 'deepseek-v4-flash' not in opencode
    assert 'deepseek-v4-pro' not in opencode

    assert 'sops.secrets."opencode/work_key"' in client
    assert 'path = "/run/secrets/opencode/work_key";' in client
    assert "work_key: ENC[" in secrets
